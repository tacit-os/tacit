package backend

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/mail"
	"regexp"
	"slices"
	"strings"
)

const draftContextLimit = 6

var draftTopicWord = regexp.MustCompile(`[\pL\pN]{4,}`)

// draftContext puts the selected thread first, then looks up correspondence
// with the recipients across the locally cached, allowed accounts.
func (s *Store) draftContext(ctx context.Context, request DraftSuggestion) ([]Message, error) {
	account, err := s.Account(ctx, request.AccountID)
	if err != nil {
		return nil, err
	}
	const usable = "mailbox NOT IN ('Drafts','Outbox','Trash','Spam')"
	messages := []Message{}
	seen := []string{}
	if request.SourceID != "" {
		source, err := s.Get(ctx, request.SourceID)
		if err != nil {
			return nil, err
		}
		if source.AccountID != account.ID {
			return nil, ErrInvalid
		}
		if !slices.Contains([]string{"Drafts", "Outbox", "Trash", "Spam"}, source.Mailbox) {
			messages = append(messages, source)
			seen = append(seen, source.ID)
		}
		if source.ConversationID != "" {
			rows, err := s.db.QueryContext(ctx, "SELECT payload FROM messages WHERE account_id=? AND conversation_id=? AND id<>? AND "+
				usable+" ORDER BY date DESC,id DESC LIMIT 2", account.ID, source.ConversationID, source.ID)
			if err != nil {
				return nil, err
			}
			thread, err := readDraftContextRows(rows)
			if err != nil {
				return nil, err
			}
			for _, m := range thread {
				messages = append(messages, m)
				seen = append(seen, m.ID)
			}
		}
	}

	addresses := []string{}
	for _, value := range request.Recipients[:min(20, len(request.Recipients))] {
		parsed, err := mail.ParseAddress(value)
		if err == nil {
			address := strings.ToLower(parsed.Address)
			if !slices.Contains(addresses, address) {
				addresses = append(addresses, address)
			}
		}
	}
	if len(addresses) == 0 {
		return messages, nil
	}
	targets, _ := json.Marshal(addresses)
	excluded, _ := json.Marshal(seen)
	query := `SELECT payload FROM messages m WHERE ` + usable +
		` AND id NOT IN (SELECT value FROM json_each(?))
		   AND (LOWER(json_extract(m.payload,'$.from.email')) IN (SELECT value FROM json_each(?))
			    OR EXISTS (SELECT 1 FROM json_each(m.payload,'$.to')
				   WHERE LOWER(json_extract(value,'$.email')) IN (SELECT value FROM json_each(?))))`
	args := []any{string(excluded), string(targets), string(targets)}
	// Demo mail never participates in context selection for a real account.
	if request.AllAccounts && account.Provider != "mock" {
		query += " AND account_id IN (SELECT id FROM accounts WHERE provider<>'mock')"
	} else {
		query += " AND account_id=?"
		args = append(args, account.ID)
	}
	topics := draftTopicWord.FindAllString(limitedMailText(request.Subject+" "+request.Instruction, 1400), 14)
	query += " ORDER BY "
	if len(topics) > 0 {
		for i, topic := range topics {
			topics[i] = `"` + topic + `"`
		}
		query += " (id IN (SELECT message_id FROM search WHERE search MATCH ?)) DESC, "
		args = append(args, strings.Join(topics, " OR "))
	}
	query += " date DESC,id DESC LIMIT ?"
	args = append(args, draftContextLimit-len(messages))
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	related, err := readDraftContextRows(rows)
	return append(messages, related...), err
}

func readDraftContextRows(rows *sql.Rows) ([]Message, error) {
	defer rows.Close()
	var messages []Message
	for rows.Next() {
		var payload []byte
		if err := rows.Scan(&payload); err != nil {
			return nil, err
		}
		var m Message
		if err := json.Unmarshal(payload, &m); err != nil {
			return nil, err
		}
		messages = append(messages, m)
	}
	return messages, rows.Err()
}
