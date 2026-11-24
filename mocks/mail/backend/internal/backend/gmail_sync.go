package backend

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"sync"
	"time"
)

type gmailImportState struct {
	ForegroundYears int
	Cutoff          time.Time
	Started         string
	Refresh         bool
}

type gmailFetch struct {
	id     string
	record gmailMessage
	body   bool
	err    error
}

func (p *InternetProvider) syncGmail(ctx context.Context, account Account, progress func(int, int)) (SyncResult, error) {
	client := p.gmail()
	if progress == nil {
		return p.Store.syncGmail(ctx, account, client, nil)
	}
	// Parallel Gmail reads can report a cooldown. Serialize it with counts
	// and stop all progress writes before the HTTP handler writes its final event.
	const waitingForProvider = -5
	var mu sync.Mutex
	closed := false
	waiting := false
	emit := func(done, total int) {
		mu.Lock()
		defer mu.Unlock()
		if closed {
			return
		}
		if done == waitingForProvider {
			waiting = true
		} else if done >= 0 && waiting && !client.cooldown.limited() {
			progress(waitingForProvider, 0)
			waiting = false
		}
		progress(done, total)
	}
	client.onLimit = func() { emit(waitingForProvider, 1) }
	defer func() {
		mu.Lock()
		closed = true
		mu.Unlock()
	}()
	return p.Store.syncGmail(ctx, account, client, emit)
}

func (s *Store) syncGmail(ctx context.Context, account Account, client gmailClient, progress func(int, int)) (SyncResult, error) {
	var result SyncResult
	cursor, err := s.gmailMetadata(ctx, gmailHistoryKey+account.ID)
	if err != nil {
		return result, err
	}
	known, err := s.cachedGmailIDs(ctx, account.ID)
	if err != nil {
		return result, err
	}
	if cursor != "" {
		ids, next, err := client.changes(ctx, cursor)
		if err == nil {
			if err := s.fetchGmail(ctx, client, account.ID, ids, known, true, true, nil, &result); err != nil {
				return result, err
			}
			return result, s.finishGmailSync(ctx, account.ID, next, &result)
		}
		if !errors.Is(err, gmailHTTPError(http.StatusNotFound)) {
			return result, err
		}
	}

	rawState, err := s.gmailMetadata(ctx, gmailImportKey+account.ID)
	if err != nil {
		return result, err
	}
	var state gmailImportState
	if rawState == "" {
		state.Started, err = client.profile(ctx)
		if err != nil {
			return result, err
		}
		state.ForegroundYears = initialImportYears
		state.Cutoff = time.Now().AddDate(-initialImportYears, 0, 0).Truncate(time.Second)
		state.Refresh = cursor != ""
		if err := s.beginGmailImport(ctx, account.ID, state); err != nil {
			return result, err
		}
		if progress != nil {
			progress(-4, 0)
		}
		account.RecentImportReady = false
	} else if err := json.Unmarshal([]byte(rawState), &state); err != nil {
		return result, err
	} else if !account.RecentImportReady && state.ForegroundYears == 0 {
		// Upgrade a five-year import before the mailbox opens. Existing cached
		// messages and the original history cursor remain valid.
		state.ForegroundYears = initialImportYears
		state.Cutoff = time.Now().AddDate(-initialImportYears, 0, 0).Truncate(time.Second)
		raw, err := json.Marshal(state)
		if err != nil {
			return result, err
		}
		if _, err := s.db.ExecContext(ctx, "UPDATE metadata SET value=? WHERE key=?", string(raw), gmailImportKey+account.ID); err != nil {
			return result, err
		}
	}

	if !account.RecentImportReady {
		if progress != nil {
			progress(importPreparing, importCheckingFolder)
		}
		recent, err := client.list(ctx, fmt.Sprintf("after:%d", state.Cutoff.Unix()-1))
		if err != nil {
			return result, err
		}
		if err := s.runGmailPhase(ctx, client, account.ID, recent, known, state.Refresh, progress, &result); err != nil {
			return result, err
		}
		if _, err := s.db.ExecContext(ctx, "INSERT OR REPLACE INTO metadata VALUES(?,?)",
			recentImportKey+account.ID, state.Cutoff.Format(time.DateOnly)); err != nil {
			return result, err
		}
	}
	if progress != nil {
		progress(-2, 0)
	}
	older, err := client.list(ctx, fmt.Sprintf("before:%d", state.Cutoff.Unix()))
	if err != nil {
		return result, err
	}
	if err := s.runGmailPhase(ctx, client, account.ID, older, known, state.Refresh, progress, &result); err != nil {
		return result, err
	}
	if state.Refresh {
		recent, err := client.list(ctx, fmt.Sprintf("after:%d", state.Cutoff.Unix()-1))
		if err != nil {
			return result, err
		}
		present := make(map[string]bool, len(recent)+len(older))
		for _, ids := range [][]string{recent, older} {
			for _, id := range ids {
				present[id] = true
			}
		}
		var missing []string
		for id, localID := range known {
			if localID != "" && !present[id] {
				missing = append(missing, id)
			}
		}
		if err := s.fetchGmail(ctx, client, account.ID, missing, known, true, false, nil, &result); err != nil {
			return result, err
		}
	}
	changed, next, err := client.changes(ctx, state.Started)
	if errors.Is(err, gmailHTTPError(http.StatusNotFound)) {
		// Finish this snapshot and verify its contents with a fresh inventory on the next pass.
		next = state.Started
	} else if err != nil {
		return result, err
	}
	if err := s.fetchGmail(ctx, client, account.ID, changed, known, true, false, nil, &result); err != nil {
		return result, err
	}
	return result, s.finishGmailSync(ctx, account.ID, next, &result)
}

func (s *Store) runGmailPhase(ctx context.Context, client gmailClient, account string, ids []string,
	known map[string]string, refresh bool, progress func(int, int), result *SyncResult) error {
	saved, total := 0, 0
	pending := make([]string, 0, len(ids))
	for _, id := range ids {
		local, exists := known[id]
		if exists && local == "" {
			continue
		}
		total++
		if exists && !refresh {
			saved++
		} else {
			pending = append(pending, id)
		}
	}
	if progress != nil {
		progress(saved, total)
	}
	return s.fetchGmail(ctx, client, account, pending, known, refresh, false, func(exists bool) {
		if exists {
			saved++
		} else {
			total--
		}
		if progress != nil {
			progress(saved, total)
		}
	}, result)
}

func (s *Store) fetchGmail(ctx context.Context, client gmailClient, account string, ids []string,
	known map[string]string, metadata, notify bool, progress func(bool), result *SyncResult) error {
	// Keep up to three requests in flight and report each message after it is committed.
	const parallel = 3
	results := make(chan gmailFetch, parallel)
	requestCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	next, inFlight := 0, 0
	for {
		for inFlight < parallel && next < len(ids) {
			id := ids[next]
			next++
			local, exists := known[id]
			if exists && local == "" {
				continue
			}
			inFlight++
			go func(id string, body bool) {
				format := "metadata"
				if body {
					format = "raw"
				}
				record, err := client.get(requestCtx, id, format)
				results <- gmailFetch{id, record, body, err}
			}(id, !metadata || !exists)
		}
		if inFlight == 0 {
			break
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case fetched := <-results:
			inFlight--
			if fetched.err != nil && !errors.Is(fetched.err, gmailHTTPError(http.StatusNotFound)) {
				return fetched.err
			}
			if err := s.saveGmailFetch(ctx, account, fetched, known, notify, result); err != nil {
				return err
			}
			if progress != nil {
				progress(fetched.err == nil && !slices.Contains(fetched.record.LabelIDs, "DRAFT"))
			}
		}
	}
	return nil
}

func (s *Store) saveGmailFetch(ctx context.Context, account string, item gmailFetch,
	known map[string]string, notify bool, result *SyncResult) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	local := known[item.id]
	if item.err != nil || slices.Contains(item.record.LabelIDs, "DRAFT") {
		if local != "" {
			if err := deleteMessage(ctx, tx, local); err != nil {
				return err
			}
			result.Received++
		}
		if err := tx.Commit(); err != nil {
			return err
		}
		delete(known, item.id)
		return nil
	}
	var message Message
	remote := gmailRemotePrefix + item.id
	err = tx.QueryRowContext(ctx, "SELECT id FROM messages WHERE account_id=? AND remote_id=?", account, remote).Scan(&local)
	if err == nil {
		message, err = read(ctx, tx, local)
	} else if errors.Is(err, sql.ErrNoRows) && item.body {
		message, err = item.record.parse()
		message.AccountID = account
		if err == nil && message.MessageID != "" && slices.Contains(message.GmailLabels, "SENT") {
			matchErr := tx.QueryRowContext(ctx, `SELECT id FROM messages WHERE account_id=? AND mailbox='Sent'
					AND remote_id LIKE 'smtp:%' AND json_extract(payload,'$.message_id')=? LIMIT 1`, account, message.MessageID).Scan(&message.ID)
			if matchErr != nil && !errors.Is(matchErr, sql.ErrNoRows) {
				return matchErr
			}
		}
		if err == nil && message.ID == "" {
			message.ID = id()
			if notify && message.Unread && message.Mailbox == "Inbox" {
				result.NewUnread++
				if !message.Automated {
					result.NewLikelyPersonal++
				}
			}
		}
	} else if errors.Is(err, sql.ErrNoRows) {
		// A local action removed the cached row while the request was in flight.
		return nil
	}
	if err != nil {
		return err
	}
	var ignored bool
	if err := tx.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM metadata WHERE key=?)",
		ignoredIMAPPrefix+account+":"+remote).Scan(&ignored); err != nil {
		return err
	}
	if ignored {
		return nil
	}
	if gmailHistoryNewer(message.GmailHistoryID, item.record.HistoryID) {
		return nil
	}
	if err := item.record.apply(&message); err != nil {
		return err
	}
	if message.ConversationID == "" {
		message.ConversationID, err = conversationFor(ctx, tx, message)
		if err != nil {
			return err
		}
	}
	if err := s.write(ctx, tx, normalise(message)); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	known[item.id] = message.ID
	result.Received++
	return nil
}

func (s *Store) cachedGmailIDs(ctx context.Context, account string) (map[string]string, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT remote_id,id FROM messages WHERE account_id=? AND remote_id LIKE 'gmail:%'
		UNION ALL SELECT value,'' FROM metadata WHERE substr(key,1,length(?))=?`,
		account, ignoredIMAPPrefix+account+":"+gmailRemotePrefix, ignoredIMAPPrefix+account+":"+gmailRemotePrefix)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	known := map[string]string{}
	for rows.Next() {
		var remote, local string
		if err := rows.Scan(&remote, &local); err != nil {
			return nil, err
		}
		known[strings.TrimPrefix(remote, gmailRemotePrefix)] = local
	}
	return known, rows.Err()
}

func (s *Store) gmailMetadata(ctx context.Context, key string) (string, error) {
	var value string
	err := s.db.QueryRowContext(ctx, "SELECT value FROM metadata WHERE key=?", key).Scan(&value)
	if errors.Is(err, sql.ErrNoRows) {
		err = nil
	}
	return value, err
}

func (s *Store) beginGmailImport(ctx context.Context, account string, state gmailImportState) error {
	raw, err := json.Marshal(state)
	if err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, query := range []string{
		"DELETE FROM search WHERE message_id IN (SELECT id FROM messages WHERE account_id=? AND remote_id LIKE 'imap:%')",
		"DELETE FROM outbox WHERE state IN ('sent','cancelled') AND message_id IN (SELECT id FROM messages WHERE account_id=? AND remote_id LIKE 'imap:%')",
		"DELETE FROM messages WHERE account_id=? AND remote_id LIKE 'imap:%'",
	} {
		if _, err := tx.ExecContext(ctx, query, account); err != nil {
			return err
		}
	}
	for _, key := range []string{recentImportKey, gmailHistoryKey, "imap-sync-snapshot:"} {
		if _, err := tx.ExecContext(ctx, "DELETE FROM metadata WHERE key=?", key+account); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, "INSERT OR REPLACE INTO metadata VALUES(?,?),(?,?)",
		gmailImportKey+account, string(raw), pendingImportKey+account, "1"); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) finishGmailSync(ctx context.Context, account, cursor string, result *SyncResult) error {
	result.LastSynced = time.Now().UnixMilli()
	snapshot, err := json.Marshal(SyncResult{LastSynced: result.LastSynced})
	if err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, "INSERT OR REPLACE INTO metadata VALUES(?,?),(?,?)",
		gmailHistoryKey+account, cursor, "imap-sync-snapshot:"+account, string(snapshot)); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM metadata WHERE key IN (?,?)",
		gmailImportKey+account, pendingImportKey+account); err != nil {
		return err
	}
	return tx.Commit()
}

func gmailHistoryNewer(local, remote string) bool {
	return len(local) > len(remote) || len(local) == len(remote) && local > remote
}
