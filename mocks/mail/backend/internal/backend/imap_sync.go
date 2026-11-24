package backend

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"maps"
	"net"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

// Progress events with a negative count describe a phase instead of a message count.
const importPreparing = -3

const (
	importAuthorizing = iota
	importConnecting
	importListingFolders
	importReadingCache
	importCheckingInbox
	importCheckingArchive
	importCheckingSent
	importCheckingSpam
	importCheckingTrash
	importCheckingFolder
	importCheckingChanges
	importWaitingForBatch
)

type imapFlags struct{ unread, flagged, important bool }

func imapImportant(flags []imap.Flag) bool {
	return slices.ContainsFunc(flags, func(flag imap.Flag) bool {
		return strings.EqualFold(string(flag), "$Important")
	})
}

type imapFlagChange struct{ before, after imapFlags }

type imapFetchPlan struct {
	imapFolder
	validity     uint32
	next         imap.UID
	mailboxCount uint32
	all          []imap.UID
	pending      []imap.UID
	cached       []imap.UID
	recent       map[imap.UID]bool
}

func (plan *imapFetchPlan) remoteID(uid imap.UID) string {
	return fmt.Sprintf("imap:%s:%d:%d", plan.remote, plan.validity, uid)
}

func (plan *imapFetchPlan) scan(client *imapclient.Client, mailbox *imap.SelectData,
	known map[string]string, seen map[string]bool, since time.Time, recentOnly bool) error {
	var criteria imap.SearchCriteria
	if recentOnly {
		criteria.Since = since
	}
	found, err := client.UIDSearch(&criteria, nil).Wait()
	if err != nil {
		return err
	}
	for _, uid := range plan.all {
		delete(seen, plan.remoteID(uid))
	}
	plan.all = found.AllUIDs()
	plan.next = mailbox.UIDNext
	plan.mailboxCount = mailbox.NumMessages
	plan.pending = nil
	plan.cached = nil
	for _, uid := range plan.all {
		remote := plan.remoteID(uid)
		seen[remote] = true
		if local, exists := known[remote]; !exists {
			plan.pending = append(plan.pending, uid)
		} else if local != "" {
			plan.cached = append(plan.cached, uid)
		}
	}
	if !since.IsZero() {
		slices.Sort(plan.pending)
		slices.Reverse(plan.pending)
	}
	plan.recent = nil
	if !since.IsZero() && !recentOnly {
		recent, err := client.UIDSearch(&imap.SearchCriteria{Since: since}, nil).Wait()
		if err != nil {
			return err
		}
		plan.recent = make(map[imap.UID]bool)
		for _, uid := range recent.AllUIDs() {
			plan.recent[uid] = true
		}
	}
	return nil
}

func importPhaseCounts(plans []imapFetchPlan, known map[string]string, recentOnly bool) (saved, total int) {
	for _, plan := range plans {
		for _, uid := range plan.all {
			if !recentOnly && plan.recent[uid] {
				continue
			}
			if local, exists := known[plan.remoteID(uid)]; exists {
				if local == "" {
					continue
				}
				saved++
			}
			total++
		}
	}
	return saved, total
}

// refreshImportPlans checks each mailbox cheaply and rescans UIDs only in
// mailboxes whose count or next UID changed since the last step.
func refreshImportPlans(client *imapclient.Client, plans []imapFetchPlan, selected *string,
	known map[string]string, seen map[string]bool, since time.Time, recentOnly bool) (bool, error) {
	options := &imap.StatusOptions{NumMessages: true, UIDNext: true, UIDValidity: true}
	commands := make([]*imapclient.StatusCommand, len(plans))
	for i := range plans {
		commands[i] = client.Status(plans[i].remote, options)
	}
	for i, command := range commands {
		status, err := command.Wait()
		if err != nil {
			return false, err
		}
		plan := &plans[i]
		if status.UIDValidity != 0 && status.UIDValidity != plan.validity {
			return true, nil
		}
		if status.NumMessages != nil && *status.NumMessages == plan.mailboxCount &&
			status.UIDNext != 0 && status.UIDNext == plan.next {
			continue
		}
		mailbox, err := client.Select(plan.remote, &imap.SelectOptions{ReadOnly: true}).Wait()
		if err != nil {
			return false, err
		}
		*selected = plan.remote
		if mailbox.UIDValidity != plan.validity {
			return true, nil
		}
		if err := plan.scan(client, mailbox, known, seen, since, recentOnly); err != nil {
			return false, err
		}
	}
	return false, nil
}

func countCachedIMAPMessages(known map[string]string, seen map[string]bool) int {
	count := 0
	for remote, id := range known {
		if id != "" && seen[remote] {
			count++
		}
	}
	return count
}

// Log only Tacit's fixed folder roles and counts, never provider folder names or mail data.
func logIMAPImportTotal(plans []imapFetchPlan, total int) {
	parts := make([]string, 0, len(plans))
	for _, plan := range plans {
		parts = append(parts, fmt.Sprintf("%s=%d", plan.local, len(plan.all)))
	}
	log.Printf("IMAP import: total=%d; server folder entries: %s", total, strings.Join(parts, ", "))
}

// SyncIMAP reconciles mapped folders together so a move can retain the local message ID.
func (p *InternetProvider) syncFolders(ctx context.Context, account Account, progress func(int, int)) (SyncResult, error) {
	var result SyncResult
	stagedImport := account.ImportPending
	liveProgress := account.ImportPending && (progress != nil || stagedImport)
	backfill := account.RecentImportReady
	var since time.Time
	if stagedImport {
		since = time.Now().AddDate(-initialImportYears, 0, 0)
		if backfill {
			var cutoff string
			if err := p.Store.db.QueryRowContext(ctx, "SELECT value FROM metadata WHERE key=?", recentImportKey+account.ID).Scan(&cutoff); err != nil {
				return result, err
			}
			var err error
			since, err = time.Parse(time.DateOnly, cutoff)
			if err != nil {
				return result, err
			}
		}
	}
	preparation := func(stage int) {
		if stagedImport && !backfill && progress != nil {
			progress(importPreparing, stage)
		}
	}
	preparation(importConnecting)
	conn, closeConn, err := p.dialMail(ctx, p.IMAP)
	if err != nil {
		return result, err
	}
	defer closeConn()
	client := imapclient.New(conn, nil)
	preparation(importAuthorizing)
	if err := p.authenticateIMAP(client); err != nil {
		return result, err
	}
	preparation(importListingFolders)
	manual, err := loadIMAPFolderSettings(ctx, p.Store.db, account.ID)
	if err != nil {
		return result, err
	}
	folders, err := listIMAPFolders(client, manual, p.accessToken != "" && (stagedImport || account.RecentImportReady))
	if err != nil {
		return result, err
	}
	preparation(importReadingCache)
	known, err := cachedIMAPLocations(ctx, p.Store.db, account.ID)
	if err != nil {
		return result, err
	}
	seen := map[string]bool{}
	var incoming []Message
	var plans []imapFetchPlan
	total := 0
	downloaded := 0
	selectedFolder := ""
	scan := func(plan *imapFetchPlan, recentOnly bool) error {
		if err := conn.SetDeadline(time.Now().Add(time.Minute)); err != nil {
			return err
		}
		selected, err := client.Select(plan.remote, &imap.SelectOptions{ReadOnly: true}).Wait()
		if err != nil {
			return err
		}
		if selected.UIDValidity == 0 {
			return errors.New("IMAP server omitted UIDVALIDITY")
		}
		if plan.validity != 0 && selected.UIDValidity != plan.validity {
			return ErrConflict
		}
		plan.validity = selected.UIDValidity
		selectedFolder = plan.remote
		return plan.scan(client, selected, known, seen, since, recentOnly)
	}
	for _, folder := range folders {
		switch folder.local {
		case "Inbox":
			preparation(importCheckingInbox)
		case "Archive":
			preparation(importCheckingArchive)
		case "Sent":
			preparation(importCheckingSent)
		case "Spam":
			preparation(importCheckingSpam)
		case "Trash":
			preparation(importCheckingTrash)
		default:
			preparation(importCheckingFolder)
		}
		plan := imapFetchPlan{imapFolder: folder}
		if err := scan(&plan, stagedImport && !backfill); err != nil {
			return result, err
		}
		if len(plan.pending) > 0 || len(plan.cached) > 0 || liveProgress {
			plans = append(plans, plan)
			total += len(plan.pending)
		}
	}

	if liveProgress {
		downloaded = countCachedIMAPMessages(known, seen)
		total += downloaded
		logIMAPImportTotal(plans, total)
	}
	phaseSaved, phaseTotal := 0, 0
	if stagedImport {
		phaseSaved, phaseTotal = importPhaseCounts(plans, known, !backfill)
	}
	report := func() {
		if progress == nil {
			return
		}
		if stagedImport {
			progress(phaseSaved, phaseTotal)
		} else {
			progress(downloaded, total)
		}
	}
	if stagedImport && backfill && progress != nil {
		progress(-2, 0)
	}
	report()
	lastCountCheck := time.Now()
	for {
		index := slices.IndexFunc(plans, func(plan imapFetchPlan) bool {
			return len(plan.pending) > 0
		})
		if index < 0 {
			if !stagedImport || backfill {
				break
			}
			// All recent batches are durable before the mailbox becomes available.
			if _, err := p.Store.db.ExecContext(ctx, "INSERT OR REPLACE INTO metadata(key,value) VALUES(?,?)",
				recentImportKey+account.ID, since.Format(time.DateOnly)); err != nil {
				return result, err
			}
			backfill = true
			if progress != nil {
				progress(-2, 0)
			}
			if err := ctx.Err(); err != nil {
				return result, err
			}
			for i := range plans {
				if err := scan(&plans[i], false); err != nil {
					if errors.Is(err, ErrConflict) {
						result.HasMore = true
						return result, nil
					}
					return result, err
				}
			}
			phaseSaved, phaseTotal = importPhaseCounts(plans, known, false)
			lastCountCheck = time.Now()
			report()
			continue
		}
		plan := &plans[index]
		preparation(importWaitingForBatch)
		if selectedFolder != plan.remote {
			if err := conn.SetDeadline(time.Now().Add(20 * time.Second)); err != nil {
				return result, err
			}
			selected, err := client.Select(plan.remote, &imap.SelectOptions{ReadOnly: true}).Wait()
			if err != nil {
				return result, err
			}
			if selected.UIDValidity != plan.validity {
				result.HasMore = true
				return result, nil
			}
			selectedFolder = plan.remote
		}
		if err := conn.SetDeadline(time.Now().Add(time.Minute)); err != nil {
			return result, err
		}
		section := &imap.FetchItemBodySection{Peek: true}
		batch := plan.pending[:min(25, len(plan.pending))]
		plan.pending = plan.pending[len(batch):]
		fetch := client.Fetch(imap.UIDSetNum(batch...), &imap.FetchOptions{UID: true, Flags: true,
			InternalDate: true, Envelope: true, BodySection: []*imap.FetchItemBodySection{section}})
		itemCount := 0
		var fetchErr error
		for data := fetch.Next(); data != nil; data = fetch.Next() {
			item, err := data.Collect()
			if err != nil {
				fetchErr = err
				break
			}
			itemCount++
			message := receivedIMAPMessage(item, section)
			message.AccountID, message.Mailbox = account.ID, plan.local
			message.RemoteID = plan.remoteID(item.UID)
			message.Unread = !slices.Contains(item.Flags, imap.FlagSeen)
			message.Flagged = slices.Contains(item.Flags, imap.FlagFlagged)
			message.Important = imapImportant(item.Flags)
			if message.Date.IsZero() {
				message.Date = item.InternalDate
			}
			incoming = append(incoming, message)
			downloaded++
			if stagedImport && (!backfill || !plan.recent[item.UID]) {
				phaseSaved++
				if !backfill {
					report()
				}
			}
		}
		if err := errors.Join(fetchErr, fetch.Close()); err != nil {
			log.Printf("IMAP sync: fetch failed (messages=%d, timeout=%t, error_type=%T)", len(batch), errors.Is(err, context.DeadlineExceeded) || errors.Is(err, os.ErrDeadlineExceeded), err)
			return result, err
		}
		if account.ImportPending && len(incoming) > 0 {
			// Checkpoint fresh messages without removing existing copies. Folder
			// removals and flags still use the complete server scan below.
			saved, err := p.Store.checkpointIMAPImport(ctx, account.ID, known, incoming)
			if err != nil {
				log.Printf("IMAP sync: checkpoint failed (messages=%d, invalid=%t, error_type=%T)", len(incoming), errors.Is(err, ErrInvalid), err)
				return result, err
			}
			if saved.HasMore {
				result.HasMore = true
				return result, nil
			}
			result.Received += saved.Received
			result.NewUnread += saved.NewUnread
			result.NewLikelyPersonal += saved.NewLikelyPersonal
			incoming = nil
		}
		// A UID can disappear between SEARCH and FETCH if another client moves it.
		if liveProgress && (itemCount != len(batch) || time.Since(lastCountCheck) >= 30*time.Second ||
			!slices.ContainsFunc(plans, func(plan imapFetchPlan) bool { return len(plan.pending) > 0 })) {
			if itemCount != len(batch) {
				// Rebuild this plan even if STATUS has not caught up yet.
				plan.next = 0
			}
			preparation(importCheckingChanges)
			retry, err := refreshImportPlans(client, plans, &selectedFolder, known, seen, since, stagedImport && !backfill)
			if err != nil {
				return result, err
			}
			if retry {
				result.HasMore = true
				return result, nil
			}
			if stagedImport {
				phaseSaved, phaseTotal = importPhaseCounts(plans, known, !backfill)
			}
			lastCountCheck = time.Now()
			previousTotal := total
			downloaded = countCachedIMAPMessages(known, seen)
			total = downloaded
			for _, plan := range plans {
				total += len(plan.pending)
			}
			if total != previousTotal {
				logIMAPImportTotal(plans, total)
			}
		}
		report()
	}
	changes, err := p.collectIMAPFlagChanges(ctx, conn, client, account.ID, plans, seen)
	if err != nil {
		return result, err
	}
	final, err := p.Store.applyIMAPFolders(ctx, account.ID, folders, known, seen, incoming, changes)
	if err == nil {
		result.Received += final.Received
		result.NewUnread += final.NewUnread
		result.NewLikelyPersonal += final.NewLikelyPersonal
		result.HasMore = final.HasMore
	}
	if err != nil || result.HasMore {
		return result, err
	}
	result.SyncedFolders = make(map[string]string, len(folders))
	for _, folder := range folders {
		result.SyncedFolders[folder.local] = folder.remote
	}
	pendingErr := p.Store.db.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM messages
		WHERE account_id=? AND mailbox='Sent' AND remote_id LIKE 'smtp:%')`, account.ID).
		Scan(&result.SentCopyPending)
	if pendingErr != nil {
		result.SentCopyPending = true
	}
	if sent := result.SyncedFolders["Sent"]; sent != "" && result.SentCopyPending {
		// The next successful import clears this status after it has matched
		// the IMAP copy, even if the preceding APPEND response was lost.
		_ = p.syncSentCopies(ctx, client, account.ID, sent, func() error {
			return conn.SetDeadline(time.Now().Add(20 * time.Second))
		})
	}
	result.LastSynced = time.Now().UnixMilli()
	snapshot, err := json.Marshal(SyncResult{LastSynced: result.LastSynced,
		SyncedFolders: result.SyncedFolders, SentCopyPending: result.SentCopyPending})
	if err == nil {
		_, err = p.Store.db.ExecContext(ctx, `INSERT INTO metadata(key,value) VALUES(?,?)
			ON CONFLICT(key) DO UPDATE SET value=excluded.value`, "imap-sync-snapshot:"+account.ID, string(snapshot))
	}
	return result, err
}

func (p *InternetProvider) collectIMAPFlagChanges(ctx context.Context, conn net.Conn, client *imapclient.Client,
	account string, plans []imapFetchPlan, seen map[string]bool) (map[string]imapFlagChange, error) {
	if !slices.ContainsFunc(plans, func(plan imapFetchPlan) bool { return len(plan.cached) > 0 }) {
		return nil, nil
	}
	flags, err := p.Store.cachedIMAPFlags(ctx, account)
	if err != nil {
		return nil, err
	}
	changes := map[string]imapFlagChange{}
	for _, plan := range plans {
		uids := slices.DeleteFunc(plan.cached, func(uid imap.UID) bool { return !seen[plan.remoteID(uid)] })
		if len(uids) == 0 {
			continue
		}
		if err := conn.SetDeadline(time.Now().Add(20 * time.Second)); err != nil {
			return nil, err
		}
		mailbox, err := client.Select(plan.remote, &imap.SelectOptions{ReadOnly: true}).Wait()
		if err != nil {
			return nil, err
		}
		if mailbox.UIDValidity != plan.validity {
			continue
		}
		for start := 0; start < len(uids); start += 100 {
			if err := conn.SetDeadline(time.Now().Add(20 * time.Second)); err != nil {
				return nil, err
			}
			items, err := client.Fetch(imap.UIDSetNum(uids[start:min(start+100, len(uids))]...),
				&imap.FetchOptions{UID: true, Flags: true}).Collect()
			if err != nil {
				return nil, err
			}
			for _, item := range items {
				remote := plan.remoteID(item.UID)
				before, exists := flags[remote]
				after := imapFlags{!slices.Contains(item.Flags, imap.FlagSeen), slices.Contains(item.Flags, imap.FlagFlagged), imapImportant(item.Flags)}
				if exists && before != after {
					changes[remote] = imapFlagChange{before, after}
				}
			}
		}
	}
	return changes, nil
}

func receivedIMAPMessage(item *imapclient.FetchMessageBuffer, section *imap.FetchItemBodySection) Message {
	message, err := ReadMIME(bytes.NewReader(item.FindBodySection(section)))
	if err == nil {
		return message
	}
	// Preserve the envelope when the provider supplied a body we cannot decode.
	// Keep the warning in the message so it is distinguishable from an empty body.
	if envelope := item.Envelope; envelope != nil {
		message.Subject = envelope.Subject
		message.MessageID = envelope.MessageID
		if len(envelope.From) > 0 {
			from := envelope.From[0]
			message.From = Address{Name: from.Name, Email: from.Addr()}
		}
	}
	message.BodyText = "Tacit could not read this message. Open it with your mail provider to view the original."
	message.BodyHTML = ""
	message.Attachments = nil
	return message
}

func (s *Store) applyIMAPFolders(ctx context.Context, account string, folders []imapFolder, known map[string]string, seen map[string]bool, incoming []Message, flags map[string]imapFlagChange) (SyncResult, error) {
	var result SyncResult
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return result, err
	}
	defer tx.Rollback()
	current, err := cachedIMAPLocations(ctx, tx, account)
	if err != nil {
		return result, err
	}
	if !maps.Equal(known, current) {
		// A local move completed while the server was being read. Retry on the next sync.
		return SyncResult{HasMore: true}, nil
	}
	mappedFolders := map[string]string{}
	for _, folder := range folders {
		mappedFolders[folder.remote] = folder.local
	}
	var missing []Message
	for remote, local := range known {
		if local == "" || seen[remote] {
			continue
		}
		loc, err := parseIMAPLocation(remote)
		if err != nil || mappedFolders[loc.mailbox] == "" {
			continue
		}
		message, err := read(ctx, tx, local)
		if err != nil {
			return result, err
		}
		if message.Mailbox == mappedFolders[loc.mailbox] || message.Mailbox == "Trash" {
			missing = append(missing, message)
		}
	}
	matches := matchIMAPMoves(missing, incoming)
	retained := map[string]bool{}
	if err := s.writeIMAPMessages(ctx, tx, account, incoming, matches, retained, &result); err != nil {
		return result, err
	}
	for _, m := range missing {
		if !retained[m.ID] {
			if err := deleteMessage(ctx, tx, m.ID); err != nil {
				return result, err
			}
			result.Received++
		}
	}
	for remote, change := range flags {
		message, err := read(ctx, tx, current[remote])
		if err != nil {
			return result, err
		}
		if (imapFlags{message.Unread, message.Flagged, message.Important}) != change.before {
			continue
		}
		message.Unread, message.Flagged, message.Important = change.after.unread, change.after.flagged, change.after.important
		if err := s.write(ctx, tx, message); err != nil {
			return result, err
		}
		result.Received++
	}
	return result, tx.Commit()
}

// Check only the incoming keys in this transaction. Full reconciliation still
// compares the complete location map before changing or removing existing rows.
func (s *Store) checkpointIMAPImport(ctx context.Context, account string, known map[string]string, incoming []Message) (SyncResult, error) {
	var result SyncResult
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return result, err
	}
	defer tx.Rollback()
	for _, message := range incoming {
		var present bool
		if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM messages WHERE account_id=? AND remote_id=?)
			OR EXISTS(SELECT 1 FROM metadata WHERE key=?)`, account, message.RemoteID,
			ignoredIMAPPrefix+account+":"+message.RemoteID).Scan(&present); err != nil {
			return result, err
		}
		if present {
			return SyncResult{HasMore: true}, nil
		}
	}
	if err := s.writeIMAPMessages(ctx, tx, account, incoming, nil, nil, &result); err != nil {
		return result, err
	}
	if err := tx.Commit(); err != nil {
		return SyncResult{}, err
	}
	for _, message := range incoming {
		known[message.RemoteID] = message.ID
	}
	return result, nil
}

func (s *Store) writeIMAPMessages(ctx context.Context, tx *sql.Tx, account string, incoming []Message,
	matches map[int]Message, retained map[string]bool, result *SyncResult) error {
	var err error
	for i, m := range incoming {
		if previous, ok := matches[i]; ok {
			m.ID, m.ConversationID = previous.ID, previous.ConversationID
			retained[m.ID] = true
			if m.Mailbox == "Trash" {
				m.TrashOrigin = previous.Mailbox
			}
		} else if m.Mailbox == "Sent" && m.MessageID != "" {
			err := tx.QueryRowContext(ctx, `SELECT id,conversation_id FROM messages
				WHERE account_id=? AND mailbox='Sent' AND remote_id LIKE 'smtp:%'
				AND json_extract(payload,'$.message_id')=? LIMIT 1`, account, m.MessageID).
				Scan(&m.ID, &m.ConversationID)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				return err
			}
		}
		if m.ID == "" {
			m.ID = id()
			m.ConversationID, err = conversationFor(ctx, tx, m)
			if err != nil {
				return err
			}
			if m.Mailbox == "Inbox" && m.Unread {
				result.NewUnread++
				if !m.Automated {
					result.NewLikelyPersonal++
				}
			}
		}
		if err := s.write(ctx, tx, normalise(m)); err != nil {
			return err
		}
		incoming[i].ID = m.ID
		result.Received++
	}
	return nil
}

func (s *Store) cachedIMAPFlags(ctx context.Context, account string) (map[string]imapFlags, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT remote_id,
		COALESCE(json_extract(payload,'$.unread'),0), COALESCE(json_extract(payload,'$.flagged'),0),
		COALESCE(json_extract(payload,'$.important'),0)
		FROM messages WHERE account_id=? AND remote_id LIKE 'imap:%'`, account)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	flags := map[string]imapFlags{}
	for rows.Next() {
		var remote string
		var value imapFlags
		if err := rows.Scan(&remote, &value.unread, &value.flagged, &value.important); err != nil {
			return nil, err
		}
		flags[remote] = value
	}
	return flags, rows.Err()
}

func cachedIMAPLocations(ctx context.Context, db interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}, account string) (map[string]string, error) {
	rows, err := db.QueryContext(ctx, `SELECT id, remote_id FROM messages
		WHERE account_id=? AND remote_id LIKE 'imap:%'
		UNION ALL SELECT '', value FROM metadata WHERE key GLOB ?`, account, ignoredIMAPPrefix+account+":*")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	known := map[string]string{}
	for rows.Next() {
		var id, remote string
		if err := rows.Scan(&id, &remote); err != nil {
			return nil, err
		}
		known[remote] = id
	}
	return known, rows.Err()
}

func matchIMAPMoves(missing, incoming []Message) map[int]Message {
	type key struct{ messageID, sender, subject, text, html string }
	identity := func(m Message) key {
		return key{m.MessageID, m.From.Email, m.Subject, m.BodyText, m.BodyHTML}
	}
	before, after := map[key][]Message{}, map[key]int{}
	for _, m := range missing {
		k := identity(m)
		before[k] = append(before[k], m)
	}
	for _, m := range incoming {
		after[identity(m)]++
	}
	result := map[int]Message{}
	for i, m := range incoming {
		k := identity(m)
		if k.messageID != "" && len(before[k]) == 1 && after[k] == 1 {
			result[i] = before[k][0]
		}
	}
	return result
}

// waitInbox waits briefly for an unsolicited Inbox change. A bounded wait also
// gives the client a regular opportunity to reconcile Trash and reconnect.
func (p *InternetProvider) waitInbox(ctx context.Context) error {
	conn, closeConn, err := p.dialMail(ctx, p.IMAP)
	if err != nil {
		return err
	}
	defer closeConn()
	updates := make(chan struct{}, 1)
	changed := func() {
		select {
		case updates <- struct{}{}:
		default:
		}
	}
	client := imapclient.New(conn, &imapclient.Options{UnilateralDataHandler: &imapclient.UnilateralDataHandler{
		Mailbox: func(*imapclient.UnilateralDataMailbox) { changed() },
		Expunge: func(uint32) { changed() },
	}})
	if err := p.authenticateIMAP(client); err != nil {
		return err
	}
	timer := time.NewTimer(12 * time.Second)
	defer timer.Stop()
	if client.Caps().Has(imap.CapIdle) || client.Caps().Has(imap.CapIMAP4rev2) {
		if _, err := client.Select("INBOX", &imap.SelectOptions{ReadOnly: true}).Wait(); err != nil {
			return err
		}
		idle, err := client.Idle()
		if err != nil {
			return err
		}
		ended := make(chan error, 1)
		go func() { ended <- idle.Wait() }()
		select {
		case err := <-ended:
			return err
		case <-updates:
		case <-timer.C:
		case <-ctx.Done():
		}
		closeConn()
		<-ended
		return ctx.Err()
	}
	select {
	case <-timer.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
