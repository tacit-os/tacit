package backend

import (
	"context"
	"encoding/base64"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

const remoteImageTestURL = "https://images.example.test/picture.gif"

func imageTestMessage(t *testing.T, store *Store, suffix string) Message {
	t.Helper()
	message := incoming("image-" + suffix)
	message.BodyHTML = `<p>Mail</p><img src="` + remoteImageTestURL + `">`
	if _, err := store.CacheBatch(ctx, "work", Batch{Messages: []Message{message}}); err != nil {
		t.Fatal(err)
	}
	var messageID string
	if err := store.db.QueryRow("SELECT id FROM messages WHERE remote_id=?", message.RemoteID).Scan(&messageID); err != nil {
		t.Fatal(err)
	}
	message, err := store.Get(ctx, messageID)
	if err != nil {
		t.Fatal(err)
	}
	return message
}

func installImageTestClient(store *Store, requests *atomic.Int32) {
	store.remoteImagesHTTP = &http.Client{Transport: gmailTestTransport(func(r *http.Request) (*http.Response, error) {
		requests.Add(1)
		data, _ := base64.StdEncoding.DecodeString("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
		response := gmailTestResponse(http.StatusOK, string(data))
		response.Header = http.Header{"Content-Type": {"image/gif"}}
		return response, nil
	})}
}

func TestRemoteImagesPersistOfflineAndDeleteWithLastMessage(t *testing.T) {
	store, _, _ := openTest(t)
	var requests atomic.Int32
	installImageTestClient(store, &requests)
	first := imageTestMessage(t, store, "first")
	second := imageTestMessage(t, store, "second")
	for _, message := range []Message{first, second} {
		if err := store.AllowMessageImages(ctx, message.ID); err != nil {
			t.Fatal(err)
		}
		image, err := store.CacheRemoteImage(ctx, message.ID, remoteImageTestURL)
		if err != nil || !strings.HasPrefix(image.Source, "tacit-image://mail/v1/messages/") {
			t.Fatalf("cache image: %v", err)
		}
	}
	path := store.path
	store.Close()
	reopened, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	reopened.remoteImagesHTTP = &http.Client{Transport: gmailTestTransport(func(*http.Request) (*http.Response, error) {
		t.Error("a cached image must not contact its server after restarting")
		return nil, errors.New("offline")
	})}
	mediaType, file, err := reopened.RemoteImageFile(ctx, first.ID, remoteImageTestURL)
	if err != nil || mediaType != "image/gif" {
		t.Fatalf("local image bytes: %s %v", mediaType, err)
	}
	file.Close()
	if _, _, err := reopened.RemoteImageFile(ctx, first.ID, "https://missing.test/no.png"); !errors.Is(err, ErrNotFound) {
		t.Fatal("missing local image fetched or accepted")
	}
	original := first.BodyHTML
	if err := reopened.ResolveRemoteImages(ctx, &first); err != nil {
		t.Fatal(err)
	}
	if !first.RemoteImagesAllowed || len(first.RemoteImages) != 1 || first.BodyHTML != original {
		t.Fatal("message-specific consent and local image did not survive restart")
	}
	if _, err := reopened.CacheRemoteImage(ctx, first.ID, remoteImageTestURL); err != nil {
		t.Fatal(err)
	}
	var digest string
	if err := reopened.db.QueryRow("SELECT digest FROM remote_images WHERE message_id=?", first.ID).Scan(&digest); err != nil {
		t.Fatal(err)
	}
	blob := filepath.Join(path+".blobs", digest)
	for index, message := range []Message{first, second} {
		if _, err := reopened.Patch(ctx, message.ID, MessagePatch{Mailbox: "Trash"}); err != nil {
			t.Fatal(err)
		}
		if err := reopened.DeleteTrashedMessage(ctx, message.ID); err != nil {
			t.Fatal(err)
		}
		if index == 0 {
			if err := reopened.collectRemoteImages(ctx); err != nil {
				t.Fatal(err)
			}
		} else {
			deadline := time.Now().Add(3 * time.Second)
			for time.Now().Before(deadline) {
				if _, err := os.Stat(blob); errors.Is(err, os.ErrNotExist) {
					break
				}
				time.Sleep(20 * time.Millisecond)
			}
		}
		_, err := os.Stat(blob)
		if index == 0 && err != nil {
			t.Fatal("deleting one message removed an image used by another")
		}
		if index == 1 && !errors.Is(err, os.ErrNotExist) {
			t.Fatal("last message deletion left its image on disk")
		}
	}
	var grants int
	if err := reopened.db.QueryRow("SELECT count(*) FROM remote_image_grants").Scan(&grants); err != nil || grants != 0 {
		t.Fatalf("orphaned grants: %d, %v", grants, err)
	}
}

func TestRemoteImageFailureCanRetryAndMoveKeepsCache(t *testing.T) {
	store, _, _ := openTest(t)
	message := imageTestMessage(t, store, "retry")
	store.remoteImagesHTTP = &http.Client{Transport: gmailTestTransport(func(*http.Request) (*http.Response, error) {
		return gmailTestResponse(http.StatusServiceUnavailable, ""), nil
	})}
	if _, err := store.CacheRemoteImage(ctx, message.ID, remoteImageTestURL); err == nil {
		t.Fatal("download failure was hidden")
	}
	var requests atomic.Int32
	installImageTestClient(store, &requests)
	if _, err := store.CacheRemoteImage(ctx, message.ID, remoteImageTestURL); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Patch(ctx, message.ID, MessagePatch{Mailbox: "Archive"}); err != nil {
		t.Fatal(err)
	}
	if err := store.ResolveRemoteImages(ctx, &message); err != nil {
		t.Fatal(err)
	}
	if len(message.RemoteImages) != 1 {
		t.Fatal("archiving lost the local image")
	}
	for _, url := range []string{"https://other.example.test/image.png", "http://images.example.test/picture.gif", "file:///etc/passwd"} {
		if _, err := store.CacheRemoteImage(ctx, message.ID, url); !errors.Is(err, ErrInvalid) {
			t.Fatalf("accepted unrelated URL %s", url)
		}
	}
	if requests.Load() != 1 {
		t.Fatal("invalid URLs reached the network")
	}
}

func TestDeletedMailCannotRegainImagesFromInflightDownload(t *testing.T) {
	store, _, _ := openTest(t)
	message := imageTestMessage(t, store, "concurrent")
	started, release := make(chan struct{}), make(chan struct{})
	store.remoteImagesHTTP = &http.Client{Transport: gmailTestTransport(func(*http.Request) (*http.Response, error) {
		close(started)
		<-release
		data, _ := base64.StdEncoding.DecodeString("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
		return gmailTestResponse(200, string(data)), nil
	})}
	done := make(chan error, 1)
	go func() {
		_, err := store.CacheRemoteImage(context.Background(), message.ID, remoteImageTestURL)
		done <- err
	}()
	<-started
	if _, err := store.Patch(ctx, message.ID, MessagePatch{Mailbox: "Trash"}); err != nil {
		close(release)
		t.Fatal(err)
	}
	if err := store.DeleteTrashedMessage(ctx, message.ID); err != nil {
		close(release)
		t.Fatal(err)
	}
	close(release)
	if err := <-done; !errors.Is(err, ErrNotFound) {
		t.Fatalf("deleted message revived: %v", err)
	}
	var images int
	if err := store.db.QueryRow("SELECT count(*) FROM remote_images WHERE message_id=?", message.ID).Scan(&images); err != nil || images != 0 {
		t.Fatalf("orphaned images: %d, %v", images, err)
	}
}

func TestOldAutomaticImageGrantsAreNotMigratedAsConsent(t *testing.T) {
	store, _, _ := openTest(t)
	m := imageTestMessage(t, store, "migration")
	var calls atomic.Int32
	installImageTestClient(store, &calls)
	if _, err := store.CacheRemoteImage(ctx, m.ID, remoteImageTestURL); err != nil {
		t.Fatal(err)
	}
	if _, err := store.db.Exec("INSERT INTO remote_image_grants VALUES(?); PRAGMA user_version=5;", m.ID); err != nil {
		t.Fatal(err)
	}
	path := store.path
	store.Close()
	reopened, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	allowed, err := reopened.MessageImagesAllowed(ctx, m.ID)
	if err != nil || allowed {
		t.Fatalf("old automatic grant became consent: %v %v", allowed, err)
	}
	_, file, err := reopened.RemoteImageFile(ctx, m.ID, remoteImageTestURL)
	if err != nil {
		t.Fatal("migration lost cached image", err)
	}
	file.Close()
}
