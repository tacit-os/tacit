package backend

import (
	"context"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

const (
	OfflineIMAP  = "offline-imap"
	stoppingIMAP = "stopping-imap"
	removingIMAP = "removing-imap"
)

type DisconnectSummary struct {
	Drafts    int `json:"drafts"`
	Waiting   int `json:"waiting"`
	Uncertain int `json:"uncertain"`
}

func (m *ManagedAccounts) DisconnectSummary(ctx context.Context, id string) (DisconnectSummary, error) {
	a, err := m.store.Account(ctx, id)
	if err != nil {
		return DisconnectSummary{}, err
	}
	switch a.Provider {
	case ManagedIMAP, OfflineIMAP, stoppingIMAP, removingIMAP:
	default:
		return DisconnectSummary{}, ErrInvalid
	}
	var v DisconnectSummary
	err = m.store.db.QueryRowContext(ctx, `SELECT
        (SELECT count(*) FROM messages WHERE account_id=? AND mailbox='Drafts'),
        count(CASE WHEN o.state IN ('queued','failed','sending') THEN 1 END),
        count(CASE WHEN o.state='uncertain' THEN 1 END)
        FROM outbox o JOIN messages m ON m.id=o.message_id WHERE m.account_id=?`, id, id).
		Scan(&v.Drafts, &v.Waiting, &v.Uncertain)
	return v, err
}

func (s *Service) DisconnectInternetAccount(ctx context.Context, m *ManagedAccounts, id string, remove bool) error {
	return s.DisconnectInternetAccountWithProgress(ctx, m, id, remove, nil)
}

func (s *Service) DisconnectInternetAccountWithProgress(ctx context.Context, m *ManagedAccounts, id string, remove bool, progress func(int64, int64)) error {
	s.syncStateMu.Lock()
	if s.disconnecting[id] {
		s.syncStateMu.Unlock()
		return ErrConflict
	}
	if s.disconnecting == nil {
		s.disconnecting = make(map[string]bool)
	}
	s.disconnecting[id] = true
	if s.syncAccount == id && s.cancelSync != nil {
		s.cancelSync()
	}
	s.syncStateMu.Unlock()
	defer func() {
		s.syncStateMu.Lock()
		delete(s.disconnecting, id)
		s.syncStateMu.Unlock()
	}()

	s.syncMu.Lock()
	defer s.syncMu.Unlock()
	s.flushMu.Lock()
	defer s.flushMu.Unlock()
	m.mu.Lock()
	defer m.mu.Unlock()

	a, err := m.store.Account(ctx, id)
	if err != nil {
		return err
	}
	switch a.Provider {
	case ManagedIMAP, stoppingIMAP, OfflineIMAP:
	case removingIMAP:
		if !remove {
			return ErrConflict
		}
	default:
		return ErrInvalid
	}
	if a.Provider == ManagedIMAP {
		next := stoppingIMAP
		if remove {
			next = removingIMAP
		}
		if err := m.store.stopInternetAccount(ctx, id, next); err != nil {
			return err
		}
	}
	if a.Provider == ManagedIMAP || a.Provider == stoppingIMAP || a.Provider == removingIMAP {
		if err := m.disconnectCredential(ctx, id); err != nil {
			return ErrCredentialStore
		}
	}
	if remove {
		if err := m.store.removeInternetCache(ctx, id, progress); err != nil {
			return err
		}
		return m.store.finishInternetRemoval(ctx, id)
	}
	_, err = m.store.db.ExecContext(ctx, "UPDATE accounts SET provider=? WHERE id=?", OfflineIMAP, id)
	return err
}

func (s *Store) stopInternetAccount(ctx context.Context, account, next string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, "UPDATE accounts SET provider=? WHERE id=?", next, account); err != nil {
		return err
	}
	rows, err := tx.QueryContext(ctx, `SELECT message_id FROM outbox
        WHERE state IN ('queued','failed') AND message_id IN (SELECT id FROM messages WHERE account_id=?)`, account)
	if err != nil {
		return err
	}
	ids, err := collectStrings(rows)
	if err != nil {
		return err
	}
	for _, id := range ids {
		message, err := read(ctx, tx, id)
		if err != nil {
			return err
		}
		message.Mailbox = "Drafts"
		if err := s.write(ctx, tx, message); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, "UPDATE outbox SET state='cancelled' WHERE message_id=? AND state IN ('queued','failed')", id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func collectStrings(rows *sql.Rows) ([]string, error) {
	defer rows.Close()
	var values []string
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, rows.Err()
}

func (s *Store) removeInternetCache(ctx context.Context, account string, progress func(int64, int64)) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, "UPDATE accounts SET provider=? WHERE id=?", removingIMAP, account); err != nil {
		return err
	}
	// Persist the digests before deleting the records so interrupted cleanup can resume.
	key := "account-removal:" + account
	if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO metadata(key,value)
        SELECT ?,json_group_array(DISTINCT digest) FROM attachments WHERE account_id=?`, key, account); err != nil {
		return err
	}
	var total int64
	if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM messages WHERE account_id=?", account).Scan(&total); err != nil {
		return err
	}
	if progress != nil {
		progress(0, total)
	}
	imageScope, _ := json.Marshal([]string{account})
	for _, deletion := range []struct{ query, value string }{
		{`DELETE FROM metadata WHERE key GLOB 'trash-undo:*' AND
		  EXISTS (SELECT 1 FROM json_each(metadata.value) j JOIN messages m ON j.key=m.id WHERE m.account_id=?)`, account},
		{"DELETE FROM metadata WHERE instr(key,?)=1", "image-policy:" + string(imageScope[:len(imageScope)-1]) + ","},
		{"DELETE FROM metadata WHERE instr(key,?)=1", ignoredIMAPPrefix + account + ":"},
		{"DELETE FROM outbox WHERE message_id IN (SELECT id FROM messages WHERE account_id=?)", account},
		{"DELETE FROM search WHERE message_id IN (SELECT id FROM messages WHERE account_id=?)", account},
		{"DELETE FROM cursors WHERE account_id=?", account},
		{"DELETE FROM metadata WHERE key=?", pendingImportKey + account},
		{"DELETE FROM metadata WHERE key=?", recentImportKey + account},
		{"DELETE FROM metadata WHERE key=?", gmailImportKey + account},
		{"DELETE FROM metadata WHERE key=?", gmailHistoryKey + account},
		{"DELETE FROM metadata WHERE key=?", imapFolderSettingsKey + account},
		{"DELETE FROM metadata WHERE key=?", "imap-sync-snapshot:" + account},
	} {
		if _, err := tx.ExecContext(ctx, deletion.query, deletion.value); err != nil {
			return err
		}
	}
	for removed := int64(0); removed < total; {
		result, err := tx.ExecContext(ctx, `DELETE FROM messages WHERE id IN (
			SELECT id FROM messages WHERE account_id=? LIMIT 250)`, account)
		if err != nil {
			return err
		}
		count, err := result.RowsAffected()
		if err != nil {
			return err
		}
		if count == 0 {
			return ErrConflict
		}
		removed += count
		if progress != nil {
			progress(removed, total)
		}
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM attachments WHERE account_id=?", account); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) finishInternetRemoval(ctx context.Context, account string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	key := "account-removal:" + account
	var data string
	if err := tx.QueryRowContext(ctx, "SELECT value FROM metadata WHERE key=?", key).Scan(&data); err != nil {
		return err
	}
	var digests []string
	if err := json.Unmarshal([]byte(data), &digests); err != nil {
		return err
	}
	for _, digest := range digests {
		var inUse bool
		if err := tx.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM attachments WHERE digest=?) OR EXISTS(SELECT 1 FROM remote_images WHERE digest=?)", digest, digest).Scan(&inUse); err != nil {
			return err
		}
		if inUse {
			continue
		}
		if decoded, err := hex.DecodeString(digest); err != nil || len(decoded) != 32 {
			return ErrInvalid
		}
		if err := os.Remove(filepath.Join(s.path+".blobs", digest)); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM accounts WHERE id=? AND provider=?", account, removingIMAP); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM metadata WHERE key=?", key); err != nil {
		return err
	}
	return tx.Commit()
}
