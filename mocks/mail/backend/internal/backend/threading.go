package backend

import (
	"context"
	"database/sql"
	"errors"
	"strings"
)

func conversationFor(ctx context.Context, tx *sql.Tx, message Message) (string, error) {
	ids := append(append([]string{}, message.References...), message.InReplyTo)
	for i := len(ids) - 1; i >= 0; i-- {
		parent := strings.TrimSpace(ids[i])
		if parent == "" {
			continue
		}
		var conversation string
		err := tx.QueryRowContext(ctx, `SELECT conversation_id FROM messages WHERE account_id=?
            AND json_extract(payload, '$.message_id')=? ORDER BY date,id LIMIT 1`, message.AccountID, parent).Scan(&conversation)
		if err == nil {
			return conversation, nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return "", err
		}
	}
	for _, parent := range ids {
		if parent = strings.TrimSpace(parent); parent != "" {
			return parent, nil
		}
	}
	return strings.TrimSpace(message.MessageID), nil
}
