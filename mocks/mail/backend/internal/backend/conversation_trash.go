package backend

import (
	"context"
	"database/sql"
	"encoding/json"
)

func (s *Store) TrashConversation(ctx context.Context, account, conversation string) (string, error) {
	if account == "" || conversation == "" {
		return "", ErrInvalid
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	rows, err := tx.QueryContext(ctx, "SELECT id, mailbox FROM messages WHERE account_id=? AND conversation_id=? AND mailbox NOT IN ('Trash','Archive','Drafts','Outbox')", account, conversation)
	if err != nil {
		return "", err
	}
	original := map[string]string{}
	for rows.Next() {
		var id, folder string
		if err = rows.Scan(&id, &folder); err != nil {
			rows.Close()
			return "", err
		}
		original[id] = folder
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return "", err
	}
	if len(original) == 0 {
		return "", ErrNotFound
	}
	messages := make([]Message, 0, len(original))
	for id := range original {
		m, e := read(ctx, tx, id)
		if e != nil {
			return "", e
		}
		messages = append(messages, m)
	}
	if err = s.moveRemote(ctx, tx, messages, "Trash"); err != nil {
		return "", err
	}
	for _, m := range messages {
		m.TrashOrigin = m.Mailbox
		m.Mailbox = "Trash"
		if err = s.write(ctx, tx, m); err != nil {
			return "", err
		}
	}
	token := id()
	data, err := json.Marshal(original)
	if err != nil {
		return "", err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO metadata(key,value) VALUES(?,?)", "trash-undo:"+token, string(data)); err != nil {
		return "", err
	}
	return token, tx.Commit()
}

func (s *Store) UndoConversationTrash(ctx context.Context, token string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var data string
	key := "trash-undo:" + token
	if err = tx.QueryRowContext(ctx, "SELECT value FROM metadata WHERE key=?", key).Scan(&data); err != nil {
		if err == sql.ErrNoRows {
			return ErrNotFound
		}
		return err
	}
	var original map[string]string
	if err = json.Unmarshal([]byte(data), &original); err != nil {
		return err
	}
	messages := make([]Message, 0, len(original))
	for id := range original {
		m, e := read(ctx, tx, id)
		if e != nil {
			return e
		}
		if m.Mailbox != "Trash" {
			return ErrConflict
		}
		messages = append(messages, m)
	}
	if err = s.restoreRemote(ctx, tx, messages, func(m Message) string { return original[m.ID] }); err != nil {
		return err
	}
	for _, m := range messages {
		m.Mailbox = original[m.ID]
		m.TrashOrigin = ""
		if err = s.write(ctx, tx, m); err != nil {
			return err
		}
	}
	if _, err = tx.ExecContext(ctx, "DELETE FROM metadata WHERE key=?", key); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) DeleteTrashedMessage(ctx context.Context, id string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = deleteTrashed(ctx, tx, id); err != nil {
		return err
	}
	return tx.Commit()
}

func deleteTrashed(ctx context.Context, tx *sql.Tx, id string) error {
	m, err := read(ctx, tx, id)
	if err != nil {
		return err
	}
	if m.Mailbox != "Trash" {
		return ErrConflict
	}
	return forgetMessage(ctx, tx, m)
}

const ignoredIMAPPrefix = "imap-ignored:"

func forgetMessage(ctx context.Context, tx *sql.Tx, m Message) error {
	if remoteMail(m.RemoteID) {
		if _, err := tx.ExecContext(ctx, "INSERT OR IGNORE INTO metadata(key,value) VALUES(?,?)",
			ignoredIMAPPrefix+m.AccountID+":"+m.RemoteID, m.RemoteID); err != nil {
			return err
		}
	}
	return deleteMessage(ctx, tx, m.ID)
}

func deleteMessage(ctx context.Context, tx *sql.Tx, id string) error {
	for _, statement := range []string{
		"DELETE FROM outbox WHERE message_id=? AND state IN ('sent','cancelled')",
		"DELETE FROM search WHERE message_id=?",
		"DELETE FROM messages WHERE id=?",
	} {
		if _, err := tx.ExecContext(ctx, statement, id); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) DeleteFolderThread(ctx context.Context, anchor string, ids []string, folder string) error {
	if folder != "Trash" && folder != "Spam" {
		return ErrConflict
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	m, err := read(ctx, tx, anchor)
	if err != nil {
		return err
	}
	if m.Mailbox != folder || m.ConversationID == "" {
		return ErrConflict
	}
	var count int
	if err = tx.QueryRowContext(ctx, "SELECT count(*) FROM messages WHERE account_id=? AND conversation_id=? AND mailbox=?", m.AccountID, m.ConversationID, folder).Scan(&count); err != nil {
		return err
	}
	if len(ids) != count || count == 0 {
		return ErrConflict
	}
	confirmedAnchor := false
	for _, id := range ids {
		confirmedAnchor = confirmedAnchor || id == anchor
		item, e := read(ctx, tx, id)
		if e != nil {
			return e
		}
		if item.AccountID != m.AccountID || item.ConversationID != m.ConversationID || item.Mailbox != folder {
			return ErrConflict
		}
		if e = forgetMessage(ctx, tx, item); e != nil {
			return e
		}
	}
	if !confirmedAnchor {
		return ErrConflict
	}
	return tx.Commit()
}

func (s *Store) RestoreTrashedThread(ctx context.Context, anchor string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	message, err := read(ctx, tx, anchor)
	if err != nil {
		return err
	}
	if message.Mailbox != "Trash" {
		return ErrConflict
	}

	ids := []string{anchor}
	if message.ConversationID != "" {
		rows, err := tx.QueryContext(ctx, "SELECT id FROM messages WHERE account_id=? AND conversation_id=? AND mailbox='Trash' AND id<>?", message.AccountID, message.ConversationID, anchor)
		if err != nil {
			return err
		}
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				rows.Close()
				return err
			}
			ids = append(ids, id)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
	}
	messages := make([]Message, 0, len(ids))
	for _, id := range ids {
		item, err := read(ctx, tx, id)
		if err != nil {
			return err
		}
		messages = append(messages, item)
	}
	destination := func(item Message) string {
		switch item.TrashOrigin {
		case "Inbox", "Drafts", "Archive":
			return item.TrashOrigin
		case "Sent", "Spam":
			if remoteMail(item.RemoteID) {
				return item.TrashOrigin
			}
			return "Inbox"
		default:
			return "Inbox"
		}
	}
	if err := s.restoreRemote(ctx, tx, messages, destination); err != nil {
		return err
	}
	for _, item := range messages {
		item.Mailbox = destination(item)
		item.TrashOrigin = ""
		if err := s.write(ctx, tx, item); err != nil {
			return err
		}
	}
	return tx.Commit()
}
