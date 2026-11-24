package backend

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
)

type setupSecrets struct {
	items map[string][]byte
}

func (s setupSecrets) Get(_ context.Context, id string) ([]byte, error) {
	return s.items[id], nil
}

func (s setupSecrets) Put(_ context.Context, id string, value []byte) error {
	s.items[id] = value
	return nil
}

func (s setupSecrets) Delete(_ context.Context, id string) error {
	delete(s.items, id)
	return nil
}

func TestManagedSetupRejectsInvalidSettingsBeforeSaving(t *testing.T) {
	store, err := Open(filepath.Join(t.TempDir(), "mail.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	secrets := setupSecrets{items: make(map[string][]byte)}
	manager := NewManagedAccounts(store, secrets)
	ctx := context.Background()
	base := InternetAccountSettings{
		Email: "user@example.test", IMAP: "imap.example.test:993", SMTP: "smtp.example.test:465", Password: "fixture",
	}
	for _, edit := range []func(*InternetAccountSettings){
		func(s *InternetAccountSettings) { s.Email = "Name <user@example.test>" },
		func(s *InternetAccountSettings) { s.IMAP = "https://imap.example.test:993" },
		func(s *InternetAccountSettings) { s.SMTP = "smtp.example.test:65536" },
		func(s *InternetAccountSettings) { s.Password = "" },
	} {
		input := base
		edit(&input)
		if _, err := manager.Connect(ctx, input); !errors.Is(err, ErrInvalid) {
			t.Fatalf("Connect returned %v, want invalid input", err)
		}
	}
	accounts, err := store.Accounts(ctx)
	if err != nil || len(accounts) != 0 || len(secrets.items) != 0 {
		t.Fatalf("rejected setup persisted an account or secret: accounts=%d secrets=%d err=%v", len(accounts), len(secrets.items), err)
	}
}
