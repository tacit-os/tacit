package backend

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func TestDisconnectKeepsDraftsAndStopsQueuedDelivery(t *testing.T) {
	store, _, service := openTest(t)
	manager, account := disconnectFixture(t, store)
	draft := disconnectDraft(t, store, account, "keep me")
	job, err := store.Queue(ctx, draft.ID, "queued-before-disconnect")
	if err != nil {
		t.Fatal(err)
	}
	summary, err := manager.DisconnectSummary(ctx, account)
	if err != nil || summary.Waiting != 1 {
		t.Fatalf("summary: %+v, %v", summary, err)
	}
	if err := service.DisconnectInternetAccount(ctx, manager, account, false); err != nil {
		t.Fatal(err)
	}
	saved, err := store.Get(ctx, draft.ID)
	if err != nil || saved.Mailbox != "Drafts" {
		t.Fatalf("kept message: %s, %v", saved.Mailbox, err)
	}
	oldJob, err := store.Job(ctx, job.ID)
	if err != nil || oldJob.State != "cancelled" {
		t.Fatalf("old job: %s, %v", oldJob.State, err)
	}
	if _, err := store.Queue(ctx, draft.ID, "offline-send"); !errors.Is(err, ErrConflict) {
		t.Fatalf("offline queue: %v", err)
	}
	a, err := store.Account(ctx, account)
	if err != nil || a.Provider != OfflineIMAP {
		t.Fatalf("account state: %s, %v", a.Provider, err)
	}
	if retained, _ := manager.secrets.Get(ctx, account); len(retained) != 0 {
		t.Fatal("credential remained after disconnect")
	}
}

func TestDisconnectRemovesOnlyTargetAccountAndUnsharedBlobs(t *testing.T) {
	store, _, service := openTest(t)
	manager, account := disconnectFixture(t, store)
	shared := []byte("shared-by-two-accounts")
	unique := []byte("unique-to-removed-account")
	other := disconnectDraft(t, store, "work", string(shared))
	targetShared := disconnectDraft(t, store, account, string(shared))
	targetUnique := disconnectDraft(t, store, account, string(unique))
	_, digest, err := attachment(ctx, store.db, account, targetUnique.Attachments[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Queue(ctx, targetShared.ID, "queued-before-removal"); err != nil {
		t.Fatal(err)
	}
	var progress [][2]int64
	if err := service.DisconnectInternetAccountWithProgress(ctx, manager, account, true, func(removed, total int64) {
		progress = append(progress, [2]int64{removed, total})
	}); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(progress, [][2]int64{{0, 2}, {2, 2}}) {
		t.Fatalf("unexpected removal progress: %v", progress)
	}
	for _, id := range []string{targetShared.ID, targetUnique.ID} {
		if _, err := store.Get(ctx, id); !errors.Is(err, ErrNotFound) {
			t.Fatalf("target message remains: %v", err)
		}
	}
	if _, err := store.Account(ctx, account); !errors.Is(err, ErrNotFound) {
		t.Fatalf("target account remains: %v", err)
	}
	if _, err := os.Stat(filepath.Join(store.path+".blobs", digest)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("unique attachment remains: %v", err)
	}
	readAttachment(t, store, other.ID, other.Attachments[0].ID, shared)
}

func disconnectFixture(t *testing.T, store *Store) (*ManagedAccounts, string) {
	t.Helper()
	account := "managed-imap-mail@example.test"
	if _, err := store.db.ExecContext(ctx, "INSERT INTO accounts(id,name,email,provider) VALUES(?,?,?,?)",
		account, "Test account", "mail@example.test", ManagedIMAP); err != nil {
		t.Fatal(err)
	}
	return NewManagedAccounts(store, setupSecrets{items: map[string][]byte{account: []byte("fixture")}}), account
}

func disconnectDraft(t *testing.T, store *Store, account, content string) Message {
	t.Helper()
	uploaded, err := store.UploadAttachment(ctx, account, "note.txt", "text/plain", bytes.NewBufferString(content), int64(len(content)))
	if err != nil {
		t.Fatal(err)
	}
	m, err := store.SaveDraft(ctx, Message{AccountID: account, Subject: "test", BodyText: content,
		To: []Address{{Email: "recipient@example.test"}}, Attachments: []Attachment{{ID: uploaded.ID}}})
	if err != nil {
		t.Fatal(err)
	}
	return m
}

type blockingSyncProvider struct {
	Provider
	started chan struct{}
}

func (p blockingSyncProvider) Receive(ctx context.Context, _ Account, _ string) (Batch, error) {
	close(p.started)
	<-ctx.Done()
	return Batch{}, ctx.Err()
}

func TestRemoveLocalMailCancelsActiveSync(t *testing.T) {
	store, _, _ := openTest(t)
	manager, account := disconnectFixture(t, store)
	if _, err := store.db.ExecContext(ctx, "UPDATE accounts SET provider=? WHERE id=?", OfflineIMAP, account); err != nil {
		t.Fatal(err)
	}
	p := blockingSyncProvider{started: make(chan struct{})}
	service := NewService(store, p)
	syncCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	synced := make(chan error, 1)
	go func() {
		_, err := service.Sync(syncCtx, account)
		synced <- err
	}()
	select {
	case <-p.started:
	case <-time.After(3 * time.Second):
		t.Fatal("sync never reached the provider")
	}
	removed := make(chan error, 1)
	go func() { removed <- service.DisconnectInternetAccount(ctx, manager, account, true) }()
	select {
	case err := <-removed:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("removal waited for an active sync to finish")
	}
	if err := <-synced; !errors.Is(err, context.Canceled) {
		t.Fatalf("sync returned %v", err)
	}
	if _, err := store.Account(ctx, account); !errors.Is(err, ErrNotFound) {
		t.Fatalf("account remains: %v", err)
	}
}
