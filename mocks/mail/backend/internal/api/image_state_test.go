package api

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"tacit.local/mailbackend/internal/backend"
	"testing"
)

func TestImageStateUsesCurrentCacheAndEffectivePermission(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mail.sqlite")
	store, err := backend.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	if err := store.Seed(context.Background()); err != nil {
		t.Fatal(err)
	}
	provider := &backend.MockProvider{Store: store}
	h := New(backend.NewService(store, provider), provider)
	type state struct {
		Cached  []backend.RemoteImage `json:"cached_images"`
		Allowed bool                  `json:"origin_allowed"`
	}
	get := func() state {
		return decode[state](t, request(t, h, "GET", "/v1/messages/seed-rich-text/image-state", nil, 200))
	}
	request(t, h, "GET", "/v1/messages/unknown/image-state", nil, 404)
	if v := get(); v.Allowed || len(v.Cached) != 0 {
		t.Fatalf("initial state: %+v", v)
	}
	request(t, h, "PUT", "/v1/settings/image-policy", map[string]string{"policy": "always"}, 200)
	if !get().Allowed {
		t.Fatal("global permission missing")
	}
	request(t, h, "PUT", "/v1/messages/seed-rich-text/image-policy", map[string]string{"policy": "never"}, 200)
	if get().Allowed {
		t.Fatal("sender override ignored")
	}
	request(t, h, "POST", "/v1/messages/seed-rich-text/image-consent", map[string]any{}, 200)
	if !get().Allowed {
		t.Fatal("explicit message consent missing")
	}
	data := []byte("GIF89a-local-image")
	sum := sha256.Sum256(data)
	digest := hex.EncodeToString(sum[:])
	file := filepath.Join(path+".blobs", digest)
	if err := os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	const raw = "https://images.example.test/picture.gif"
	if _, err := db.Exec("INSERT INTO remote_images VALUES(?,?,?,?)", "seed-rich-text", raw, digest, "image/gif"); err != nil {
		t.Fatal(err)
	}
	v := get()
	if len(v.Cached) != 1 || v.Cached[0].URL != raw || !strings.HasPrefix(v.Cached[0].Source, "tacit-image:") {
		t.Fatalf("cache state: %+v", v)
	}
	if err := os.Remove(file); err != nil {
		t.Fatal(err)
	}
	if len(get().Cached) != 0 {
		t.Fatal("stale image inventory survived removed file")
	}
}
