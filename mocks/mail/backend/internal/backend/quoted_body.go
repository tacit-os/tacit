package backend

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"

	"tacit.local/quotedbody"
)

func (s *Store) prepareBodyParts(ctx context.Context, tx *sql.Tx, m Message) (*BodyParts, error) {
	// Drafts are edited and sent in full. Reader-only transforms never affect them.
	if m.Mailbox == "Drafts" || m.Mailbox == "Outbox" {
		return nil, nil
	}
	hash := sha256.New()
	var length [8]byte
	binary.LittleEndian.PutUint64(length[:], uint64(len(m.BodyText)))
	hash.Write(length[:])
	io.WriteString(hash, m.BodyText)
	io.WriteString(hash, m.BodyHTML)
	source := hex.EncodeToString(hash.Sum(nil))
	var cached sql.NullString
	err := tx.QueryRowContext(ctx, "SELECT json_extract(payload,'$.body_parts') FROM messages WHERE id=?", m.ID).Scan(&cached)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	if cached.Valid {
		var previous BodyParts
		if json.Unmarshal([]byte(cached.String), &previous) == nil && previous.Version == quotedbody.Version && previous.Source == source {
			return &previous, nil
		}
	}
	return &BodyParts{Version: quotedbody.Version, Source: source, Text: quotedbody.SplitText(m.BodyText), HTML: quotedbody.SplitHTML(m.BodyHTML)}, nil
}

// upgradeBodyParts refreshes already-derived data from older algorithms before
// serving any messages. Legacy messages without parts remain untouched; this
// is not a whole-mailbox backfill and never changes provider or original data.
func (s *Store) upgradeBodyParts() error {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	rows, err := tx.QueryContext(ctx, `SELECT id FROM messages
 WHERE json_type(payload,'$.body_parts')='object'
 AND coalesce(json_extract(payload,'$.body_parts.version'),0) < ?
 AND mailbox NOT IN ('Drafts','Outbox')`, quotedbody.Version)
	if err != nil {
		return err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	// Keep only IDs in memory, even when many cached bodies need upgrading.
	for _, id := range ids {
		message, err := read(ctx, tx, id)
		if err != nil {
			return err
		}
		parts, err := s.prepareBodyParts(ctx, tx, message)
		if err != nil {
			return err
		}
		raw, err := json.Marshal(parts)
		if err != nil {
			return err
		}
		if _, err = tx.ExecContext(ctx, `UPDATE messages SET payload=json_set(payload,'$.body_parts',json(?)) WHERE id=?`, string(raw), message.ID); err != nil {
			return err
		}
	}
	return tx.Commit()
}
