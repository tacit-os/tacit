package backend

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
)

type ImagePolicy struct {
	Policy string `json:"policy"`
	Source string `json:"source"`
}

func (s *Store) ImagePolicy(ctx context.Context, messageID, policy string) (ImagePolicy, error) {
	key := "image-policy"
	if messageID != "" {
		message, err := s.Get(ctx, messageID)
		if err != nil {
			return ImagePolicy{}, err
		}
		sender := strings.ToLower(strings.TrimSpace(message.From.Email))
		if sender == "" {
			return ImagePolicy{}, ErrInvalid
		}
		scope, _ := json.Marshal([]string{message.AccountID, sender})
		key += ":" + string(scope)
	}
	if policy != "" {
		if policy != "always" && policy != "never" && (policy != "ask_first" || messageID != "") {
			return ImagePolicy{}, ErrInvalid
		}
		if _, err := s.db.ExecContext(ctx, "INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", key, policy); err != nil {
			return ImagePolicy{}, err
		}
	}
	if messageID != "" {
		err := s.db.QueryRowContext(ctx, "SELECT value FROM metadata WHERE key=?", key).Scan(&policy)
		if err == nil {
			return ImagePolicy{Policy: policy, Source: "sender"}, nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return ImagePolicy{}, err
		}
	}
	err := s.db.QueryRowContext(ctx, "SELECT value FROM metadata WHERE key='image-policy'").Scan(&policy)
	if errors.Is(err, sql.ErrNoRows) {
		return ImagePolicy{Policy: "ask_first", Source: "default"}, nil
	}
	return ImagePolicy{Policy: policy, Source: "global"}, err
}

// Explicit one-message consent is independent of the sender-wide/global defaults.
func (s *Store) AllowMessageImages(ctx context.Context, messageID string) error {
	if _, err := s.Get(ctx, messageID); err != nil {
		return err
	}
	_, err := s.db.ExecContext(ctx, "INSERT OR IGNORE INTO remote_image_grants VALUES(?)", messageID)
	return err
}

func (s *Store) MessageImagesAllowed(ctx context.Context, messageID string) (bool, error) {
	message, err := s.Get(ctx, messageID)
	if err != nil {
		return false, err
	}
	var granted bool
	if err := s.db.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM remote_image_grants WHERE message_id=?)", messageID).Scan(&granted); err != nil {
		return false, err
	}
	if granted {
		return true, nil
	}
	// Sender-less messages still inherit the app-wide preference.
	scope := messageID
	if strings.TrimSpace(message.From.Email) == "" {
		scope = ""
	}
	policy, err := s.ImagePolicy(ctx, scope, "")
	return policy.Policy == "always", err
}
