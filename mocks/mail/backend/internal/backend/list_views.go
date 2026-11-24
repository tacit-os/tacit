package backend

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"
	"sync"

	"golang.org/x/text/collate"
	"golang.org/x/text/language"
	"modernc.org/sqlite"
)

// A list query returns representatives, not full messages. Its total is the number
// of rows after grouping; message counters continue to count individual messages.
type ViewQuery struct {
	Query
	Filter, Sort, Generation, Locale, SelectedID, GmailCategory string
	SearchMode                                                  bool
}
type ViewMessage struct {
	Message
	FolderMessageCount int  `json:"folder_message_count,omitempty"`
	FolderStarred      bool `json:"folder_starred"`
	FolderOtherStarred bool `json:"folder_other_starred"`
}
type ViewPage struct {
	MissingID    string        `json:"missing_id,omitempty"`
	Messages     []ViewMessage `json:"messages"`
	Total        int           `json:"total"`
	MessageTotal int           `json:"message_total"`
	Generation   string        `json:"generation"`
}

func init() {
	// The collator has scratch buffers and is shared by independent stores.
	var mu sync.Mutex
	sender := collate.New(language.Und)
	locale := "und"
	sqlite.MustRegisterCollationUtf8("mail_sender", func(a, b string) int {
		mu.Lock()
		defer mu.Unlock()
		leftLocale, left, _ := strings.Cut(a, "\x00")
		rightLocale, right, _ := strings.Cut(b, "\x00")
		if leftLocale != rightLocale {
			return strings.Compare(a, b)
		}
		if locale != leftLocale {
			locale = leftLocale
			sender = collate.New(language.Make(locale))
		}
		return sender.CompareString(left, right)
	})
}

// Keep the small projection beside the authoritative message, transactionally.
// List reads never decode HTML, remote-image manifests or full text bodies. The
// triggers cover imports, flag changes, moves, drafts, deletion and account removal.
func (s *Store) initListViews() error {
	const projection = `SELECT id,account_id,conversation_id,mailbox,
        CAST(strftime('%s',substr(date,1,19)||'Z') AS INTEGER)*1000 +
            CAST(substr((CASE WHEN substr(date,20,1)='.' THEN substr(date,21) ELSE '' END)||'000',1,3) AS INTEGER),
        COALESCE(json_extract(payload,'$.unread'),0),
        COALESCE(json_extract(payload,'$.flagged'),0) OR EXISTS
            (SELECT 1 FROM json_each(payload,'$.gmail_labels') WHERE value='STARRED'),
        mailbox='Inbox' AND EXISTS
            (SELECT 1 FROM json_each(payload,'$.gmail_labels') WHERE value='SENT'),
        COALESCE(NULLIF(json_extract(payload,'$.from.name'),''),json_extract(payload,'$.from.email'),''),
        COALESCE(json_array_length(payload,'$.attachments'),0),
        json_set(json_remove(payload,'$.body_html','$.body_parts','$.remote_images','$.references'),
            '$.body_text',substr(COALESCE(json_extract(payload,'$.body_text'),''),1,512),
            '$.has_html',json(CASE WHEN length(COALESCE(json_extract(payload,'$.body_html'),''))>0 THEN 'true' ELSE 'false' END),
            '$.attachments',json(COALESCE((SELECT json_group_array(json_set(value,'$.inline',json(
                CASE WHEN json_extract(value,'$.inline') OR instr(COALESCE(json_extract(payload,'$.body_html'),''),'cid:'||json_extract(value,'$.id'))>0
                THEN 'true' ELSE 'false' END))) FROM json_each(payload,'$.attachments')),'[]')))
        FROM messages`
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.Exec(`
        CREATE TABLE IF NOT EXISTS message_list (
            id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
            account_id TEXT NOT NULL, conversation_id TEXT NOT NULL, mailbox TEXT NOT NULL,
            date INTEGER NOT NULL, unread INTEGER NOT NULL, starred INTEGER NOT NULL,
            gmail_sent INTEGER NOT NULL, sender TEXT NOT NULL, attachments INTEGER NOT NULL,
            summary TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS message_list_folder ON message_list(account_id,mailbox,date DESC,id DESC);
        CREATE INDEX IF NOT EXISTS message_list_thread ON message_list(account_id,conversation_id,date DESC,id DESC);
        CREATE TABLE IF NOT EXISTS message_list_generation (id INTEGER PRIMARY KEY CHECK(id=1), value INTEGER NOT NULL);
        INSERT OR IGNORE INTO message_list_generation VALUES(1,0);
        INSERT OR IGNORE INTO message_list ` + projection + ` WHERE id NOT IN (SELECT id FROM message_list);
        CREATE TRIGGER IF NOT EXISTS message_list_insert AFTER INSERT ON messages BEGIN
            DELETE FROM message_list WHERE id=NEW.id;
            INSERT INTO message_list ` + projection + ` WHERE id=NEW.id;
            UPDATE message_list_generation SET value=value+1 WHERE id=1;
        END;
        CREATE TRIGGER IF NOT EXISTS message_list_update AFTER UPDATE ON messages BEGIN
            DELETE FROM message_list WHERE id=NEW.id;
            INSERT INTO message_list ` + projection + ` WHERE id=NEW.id;
            UPDATE message_list_generation SET value=value+1 WHERE id=1;
        END;
        CREATE TRIGGER IF NOT EXISTS message_list_delete AFTER DELETE ON messages BEGIN
            DELETE FROM message_list WHERE id=OLD.id;
            UPDATE message_list_generation SET value=value+1 WHERE id=1;
        END;`)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) ListView(ctx context.Context, q ViewQuery) (ViewPage, error) {
	p := ViewPage{Messages: []ViewMessage{}}
	if q.Locale == "" {
		q.Locale = "und"
	}
	if len(q.Locale) > 64 {
		return p, ErrInvalid
	}
	if _, err := language.Parse(q.Locale); err != nil {
		return p, ErrInvalid
	}
	if q.Limit == 0 {
		q.Limit = 100
	}
	if q.Limit < 1 || q.Limit > 100 || q.Offset < 0 {
		return p, ErrInvalid
	}
	if q.Filter != "" && q.Filter != "All mail" && q.Filter != "Unread" && q.Filter != "Starred" && q.Filter != "With attachments" {
		return p, ErrInvalid
	}
	if q.Sort != "" && q.Sort != "Newest first" && q.Sort != "Oldest first" && q.Sort != "Sender" && q.Sort != "Unread first" {
		return p, ErrInvalid
	}
	switch q.GmailCategory {
	case "", "CATEGORY_PERSONAL", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES", "CATEGORY_FORUMS":
	default:
		return p, ErrInvalid
	}
	where := ` WHERE mailbox NOT IN ('Drafts','Outbox')`
	args := []any{}
	searching := q.SearchMode || strings.TrimSpace(q.Search) != ""
	if !searching {
		if q.AccountID != "" {
			where += ` AND account_id=?`
			args = append(args, q.AccountID)
		}
		switch q.Mailbox {
		case "Starred":
			where += ` AND starred AND mailbox!='Trash'`
		case "Sent":
			where += ` AND (mailbox='Sent' OR gmail_sent)`
		case "Inbox":
			where += ` AND mailbox='Inbox' AND NOT gmail_sent`
		default:
			where += ` AND mailbox=?`
			args = append(args, q.Mailbox)
		}
		if q.GmailCategory != "" && q.Mailbox == "Inbox" {
			where += ` AND (json_extract(summary,'$.remote_id') LIKE 'gmail:%' OR COALESCE(json_array_length(summary,'$.gmail_labels'),0)>0)`
			if q.GmailCategory == "CATEGORY_PERSONAL" {
				// Gmail can omit PERSONAL on otherwise uncategorized mail.
				where += ` AND (EXISTS(SELECT 1 FROM json_each(summary,'$.gmail_labels') WHERE value='CATEGORY_PERSONAL')
                    OR NOT EXISTS(SELECT 1 FROM json_each(summary,'$.gmail_labels') WHERE value IN ('CATEGORY_PROMOTIONS','CATEGORY_SOCIAL','CATEGORY_UPDATES','CATEGORY_FORUMS')))`
			} else {
				where += ` AND EXISTS(SELECT 1 FROM json_each(summary,'$.gmail_labels') WHERE value=?)`
				args = append(args, q.GmailCategory)
			}
		}
	} else if strings.TrimSpace(q.Search) != "" {
		fields := strings.Fields(q.Search)
		for i, f := range fields {
			fields[i] = `"` + strings.ReplaceAll(f, `"`, `""`) + `"*`
		}
		where += ` AND id IN (SELECT message_id FROM search WHERE search MATCH ?)`
		args = append(args, strings.Join(fields, " AND "))
	}
	switch q.Filter {
	case "Unread":
		where += ` AND unread`
	case "Starred":
		where += ` AND starred`
	case "With attachments":
		where += ` AND attachments>0`
	}
	partition := `id`
	if !searching && (q.Mailbox == "Inbox" || q.Mailbox == "Sent" || q.Mailbox == "Trash" || q.Mailbox == "Archive") {
		partition = `account_id,conversation_id,CASE WHEN conversation_id='' THEN id ELSE '' END`
	}
	cte := `WITH ranked AS (
        SELECT *,row_number() OVER (PARTITION BY ` + partition + ` ORDER BY date DESC,id DESC) AS rank,
            count(*) OVER (PARTITION BY ` + partition + `) AS thread_count,
            sum(starred) OVER (PARTITION BY ` + partition + `) AS thread_stars
        FROM message_list` + where + `), representatives AS (SELECT * FROM ranked WHERE rank=1) `
	order := `date DESC,id DESC`
	if !searching {
		switch q.Sort {
		case "Oldest first":
			order = `date ASC,id ASC`
		case "Sender":
			order = `(?||char(0)||sender) COLLATE mail_sender,date DESC,id DESC`
		case "Unread first":
			order = `unread DESC,date DESC,id DESC`
		}
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return p, err
	}
	defer tx.Rollback()
	var generation int64
	if err = tx.QueryRowContext(ctx, `SELECT value FROM message_list_generation WHERE id=1`).Scan(&generation); err != nil {
		return p, err
	}
	p.Generation = strconv.FormatInt(generation, 10)
	// Never combine pages from different mailbox versions. The client retries the
	// complete query if an import/mutation occurred between local HTTP requests.
	if q.Generation != "" && q.Generation != p.Generation {
		return p, ErrConflict
	}
	if q.SelectedID != "" {
		var exists bool
		if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM messages WHERE id=?)`, q.SelectedID).Scan(&exists); err != nil {
			return p, err
		}
		if !exists {
			p.MissingID = q.SelectedID
		}
	}
	if err = tx.QueryRowContext(ctx, cte+`SELECT count(*),COALESCE(sum(thread_count),0) FROM representatives`, args...).Scan(&p.Total, &p.MessageTotal); err != nil {
		return p, err
	}
	pageArgs := append([]any{}, args...)
	if !searching && q.Sort == "Sender" {
		pageArgs = append(pageArgs, q.Locale)
	}
	pageArgs = append(pageArgs, q.Limit, q.Offset)
	rows, err := tx.QueryContext(ctx, cte+`SELECT summary,thread_count,thread_stars FROM representatives ORDER BY `+order+` LIMIT ? OFFSET ?`, pageArgs...)
	if err != nil {
		return p, err
	}
	for rows.Next() {
		var raw []byte
		var m ViewMessage
		var stars int
		if err = rows.Scan(&raw, &m.FolderMessageCount, &stars); err != nil {
			break
		}
		if err = json.Unmarshal(raw, &m.Message); err != nil {
			break
		}
		m.FolderStarred = stars > 0
		ownStar := m.Flagged
		for _, label := range m.GmailLabels {
			ownStar = ownStar || label == "STARRED"
		}
		if ownStar {
			stars--
		}
		m.FolderOtherStarred = stars > 0
		p.Messages = append(p.Messages, m)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return p, err
	}
	return p, tx.Commit()
}
