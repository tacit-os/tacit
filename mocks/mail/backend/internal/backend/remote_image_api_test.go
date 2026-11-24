package backend_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"tacit.local/mailbackend/internal/api"
	"tacit.local/mailbackend/internal/backend"
)

type imageOriginTransport func(*http.Request) (*http.Response, error)

func (f imageOriginTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

const policyOrigin = "https://images.example.test/picture.gif?q=a%20b&size=2"

func policyFixture(t *testing.T) (*backend.Store, string, *atomic.Int32) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "mail.sqlite")
	store, err := backend.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	if err := store.Seed(context.Background()); err != nil {
		t.Fatal(err)
	}
	calls := &atomic.Int32{}
	installPolicyOrigin(t, store, calls)
	return store, path, calls
}
func installPolicyOrigin(t *testing.T, store *backend.Store, calls *atomic.Int32) {
	t.Helper()
	data, _ := base64.StdEncoding.DecodeString("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
	backend.SetImageOriginClientForTest(store, &http.Client{Transport: imageOriginTransport(func(r *http.Request) (*http.Response, error) {
		calls.Add(1)
		if r.Header.Get("X-Allow-Origin-Fetch") != "" || r.Header.Get("Cache-Control") != "" {
			t.Error("private cache controls leaked to origin")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": {"image/gif"}}, Body: io.NopCloser(bytes.NewReader(data))}, nil
	})})
}
func policyMessage(t *testing.T, store *backend.Store, account, id string) backend.Message {
	t.Helper()
	message := backend.Message{RemoteID: id, ConversationID: id, Mailbox: "Inbox", Date: time.Now(),
		From: backend.Address{Email: "sender@example.test"}, Subject: id, BodyText: "Image consent",
		BodyHTML: `<img src="` + policyOrigin + `"><img src="` + policyOrigin + `&second=1">`}
	if _, err := store.CacheBatch(context.Background(), account, backend.Batch{Messages: []backend.Message{message}}); err != nil {
		t.Fatal(err)
	}
	messages, err := store.Conversation(context.Background(), account, id)
	if err != nil || len(messages) != 1 {
		t.Fatalf("message fixture: %v", err)
	}
	return messages[0]
}
func policyHandler(store *backend.Store) http.Handler {
	provider := &backend.MockProvider{Store: store}
	return api.New(backend.NewService(store, provider), provider)
}
func policyRequest(h http.Handler, method, path string, body any) *httptest.ResponseRecorder {
	var data bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&data).Encode(body)
	}
	req := httptest.NewRequest(method, path, &data)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	response := httptest.NewRecorder()
	h.ServeHTTP(response, req)
	return response
}
func setPolicy(t *testing.T, h http.Handler, id, value string) {
	t.Helper()
	path := "/v1/settings/image-policy"
	if id != "" {
		path = "/v1/messages/" + id + "/image-policy"
	}
	if w := policyRequest(h, "PUT", path, map[string]string{"policy": value}); w.Code != 200 {
		t.Fatalf("save policy: %d %s", w.Code, w.Body.String())
	}
}
func imageRequest(h http.Handler, id, raw string, cacheOnly bool) *httptest.ResponseRecorder {
	req := httptest.NewRequest("GET", "/v1/messages/"+id+"/remote-image?url="+url.QueryEscape(raw), nil)
	if cacheOnly {
		req.Header.Set("Cache-Control", "only-if-cached")
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	return w
}

func TestImageProxyUsesAppSenderAndMessagePreferences(t *testing.T) {
	for _, row := range []struct {
		name, global, sender string
		grant, allowed       bool
	}{
		{"app asks", "ask_first", "", false, false},
		{"app always", "always", "", false, true},
		{"app never", "never", "", false, false},
		{"sender blocks app always", "always", "never", false, false},
		{"sender exception to app never", "never", "always", false, true},
		{"message consent with app never", "never", "", true, true},
		{"message consent with sender never", "always", "never", true, true},
	} {
		t.Run(row.name, func(t *testing.T) {
			store, _, calls := policyFixture(t)
			m := policyMessage(t, store, "work", "policy-test")
			h := policyHandler(store)
			setPolicy(t, h, "", row.global)
			if row.sender != "" {
				setPolicy(t, h, m.ID, row.sender)
			}
			if row.grant {
				if w := policyRequest(h, "POST", "/v1/messages/"+m.ID+"/image-consent", nil); w.Code != 200 {
					t.Fatal(w.Body.String())
				}
			}
			probe := imageRequest(h, m.ID, policyOrigin, true)
			if probe.Code != 504 || calls.Load() != 0 {
				t.Fatal("cache-only probe fetched an origin")
			}
			if (probe.Header().Get("X-Mail-Image-Origin-Allowed") == "true") != row.allowed {
				t.Fatal("incorrect permission hint")
			}
			normal := imageRequest(h, m.ID, policyOrigin, false)
			if row.allowed {
				if normal.Code != 200 || calls.Load() != 1 || normal.Header().Get("Content-Type") != "image/gif" {
					t.Fatalf("expected origin image: %d %s", normal.Code, normal.Body.String())
				}
				// Cached images remain readable after all automatic permissions are revoked.
				setPolicy(t, h, "", "never")
				setPolicy(t, h, m.ID, "never")
				if w := imageRequest(h, m.ID, policyOrigin, true); w.Code != 200 || calls.Load() != 1 {
					t.Fatal("cache hit was refetched or blocked")
				}
			} else if normal.Code != 504 || calls.Load() != 0 {
				t.Fatalf("denied image fetched: %d", normal.Code)
			}
		})
	}
}

func TestMessageConsentPersistsWithoutGrantingOtherMailOrAccounts(t *testing.T) {
	store, path, calls := policyFixture(t)
	m := policyMessage(t, store, "work", "one")
	other := policyMessage(t, store, "work", "two")
	personal := policyMessage(t, store, "personal", "three")
	h := policyHandler(store)
	setPolicy(t, h, "", "never")
	if w := policyRequest(h, "POST", "/v1/messages/"+m.ID+"/image-consent", nil); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	store.Close()
	reopened, err := backend.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	installPolicyOrigin(t, reopened, calls)
	h = policyHandler(reopened)
	if w := imageRequest(h, m.ID, policyOrigin, false); w.Code != 200 {
		t.Fatalf("lost message consent after restart: %d", w.Code)
	}
	for _, other := range []backend.Message{other, personal} {
		if w := imageRequest(h, other.ID, policyOrigin, false); w.Code != 504 {
			t.Fatal("message consent escaped its scope")
		}
	}
	setPolicy(t, h, m.ID, "always")
	if w := imageRequest(h, other.ID, policyOrigin, false); w.Code != 200 {
		t.Fatal("same-account sender permission was ignored")
	}
	if w := imageRequest(h, personal.ID, policyOrigin, false); w.Code != 504 {
		t.Fatal("sender permission escaped its account")
	}
}

func TestAutomaticDownloadsDoNotBecomeMessageConsent(t *testing.T) {
	store, _, calls := policyFixture(t)
	m := policyMessage(t, store, "work", "automatic")
	h := policyHandler(store)
	setPolicy(t, h, "", "always")
	if w := imageRequest(h, m.ID, policyOrigin, false); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	setPolicy(t, h, "", "never")
	if w := imageRequest(h, m.ID, policyOrigin+"&second=1", false); w.Code != 504 || calls.Load() != 1 {
		t.Fatal("automatic download granted permanent message permission")
	}
}
