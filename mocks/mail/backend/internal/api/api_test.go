package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"tacit.local/mailbackend/internal/backend"
	"testing"
	"time"
)

func apiTest(t *testing.T) (http.Handler, *backend.Store) {
	t.Helper()
	s, e := backend.Open(filepath.Join(t.TempDir(), "mail.sqlite"))
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { s.Close() })
	if e = s.Seed(context.Background()); e != nil {
		t.Fatal(e)
	}
	p := &backend.MockProvider{Store: s}
	return New(backend.NewService(s, p), p), s
}
func request(t *testing.T, h http.Handler, method, path string, body any, want int) *httptest.ResponseRecorder {
	t.Helper()
	var b bytes.Buffer
	if body != nil {
		json.NewEncoder(&b).Encode(body)
	}
	r := httptest.NewRequest(method, path, &b)
	if body != nil {
		r.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != want {
		t.Fatalf("%s %s: %d %s", method, path, w.Code, w.Body.String())
	}
	return w
}
func decode[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if e := json.Unmarshal(w.Body.Bytes(), &v); e != nil {
		t.Fatal(e)
	}
	return v
}
func TestImportStreamReportsCompletion(t *testing.T) {
	h, _ := apiTest(t)
	w := request(t, h, "POST", "/v1/sync/import", map[string]string{"account_id": "work"}, 200)
	if w.Header().Get("Content-Type") != "application/x-ndjson" || !w.Flushed {
		t.Fatal("import should flush newline-delimited events")
	}
	decoder := json.NewDecoder(w.Body)
	var start, end map[string]any
	if err := decoder.Decode(&start); err != nil || start["started"] != true {
		t.Fatalf("start event: %v, %v", start, err)
	}
	if err := decoder.Decode(&end); err != nil || end["done"] != true || end["ok"] != true {
		t.Fatalf("completion event: %v, %v", end, err)
	}
}

func TestAPIReceiveSearchDraftSendAndAttachments(t *testing.T) {
	h, s := apiTest(t)
	request(t, h, "GET", "/v1/health", nil, 200)
	a := upload(t, h, "work", "sample.txt", []byte("sample"))
	incoming := map[string]any{"account_id": "work", "message": map[string]any{"remote_id": "api-remote", "conversation_id": "api-thread", "from": map[string]string{"email": "new@example.org", "name": "New sender"}, "subject": "API search needle", "body_text": "A local received message", "mailbox": "Inbox", "unread": true, "attachments": []any{map[string]string{"id": a.ID}}}}
	request(t, h, "POST", "/v1/mock/incoming", incoming, 201)
	request(t, h, "POST", "/v1/sync", map[string]string{"account_id": "work"}, 200)
	p := decode[backend.Page](t, request(t, h, "GET", "/v1/messages?q=needle&account_id=work", nil, 200))
	if p.Total != 1 {
		t.Fatal("search did not receive message")
	}
	m := decode[backend.Message](t, request(t, h, "GET", "/v1/messages/"+p.Messages[0].ID, nil, 200))
	if len(m.Attachments) != 1 || len(m.Attachments[0].Data) != 0 {
		t.Fatal("message response should return attachment metadata, not blobs")
	}
	w := request(t, h, "GET", "/v1/messages/"+m.ID+"/attachments/"+m.Attachments[0].ID, nil, 200)
	if w.Body.String() != "sample" || w.Header().Get("Content-Disposition") == "" {
		t.Fatal("attachment content")
	}
	request(t, h, "PATCH", "/v1/messages/"+m.ID, map[string]any{"unread": false}, 200)
	conv := decode[[]backend.Message](t, request(t, h, "GET", "/v1/conversations/api-thread?account_id=work", nil, 200))
	if len(conv) != 1 {
		t.Fatal("conversation")
	}
	d := decode[backend.Message](t, request(t, h, "POST", "/v1/drafts", map[string]any{"account_id": "work", "conversation_id": "api-thread", "to": []any{map[string]string{"email": "new@example.org"}}, "subject": "Re: API search needle", "body_text": "An explicit mock reply"}, 201))
	job := decode[backend.Job](t, request(t, h, "POST", "/v1/send", map[string]string{"draft_id": d.ID, "idempotency_key": "api-send"}, 202))
	type jobPage struct {
		Jobs []backend.Job `json:"jobs"`
	}
	pending := decode[jobPage](t, request(t, h, "GET", "/v1/outbox", nil, 200))
	if len(pending.Jobs) != 1 || pending.Jobs[0].ID != job.ID || pending.Jobs[0].State != "queued" {
		t.Fatalf("queued jobs: %+v", pending.Jobs)
	}
	request(t, h, "POST", "/v1/mock/flush", map[string]any{}, 200)
	done := decode[backend.Job](t, request(t, h, "GET", "/v1/outbox/"+job.ID, nil, 200))
	if done.State != "sent" {
		t.Fatalf("job: %+v", done)
	}
	if remaining := decode[jobPage](t, request(t, h, "GET", "/v1/outbox", nil, 200)); len(remaining.Jobs) != 0 {
		t.Fatalf("sent job still in active outbox: %+v", remaining.Jobs)
	}
	stored, _ := s.Get(context.Background(), d.ID)
	if stored.Mailbox != "Sent" {
		t.Fatal("not cached in Sent")
	}
}
func TestAPIRejectsBadInputAndBrowserOrigins(t *testing.T) {
	h, _ := apiTest(t)
	request(t, h, "GET", "/v1/messages?limit=no", nil, 400)
	request(t, h, "GET", "/v1/messages/missing", nil, 404)
	request(t, h, "POST", "/v1/send", map[string]string{"draft_id": "missing"}, 400)
	for _, body := range []string{`{"unknown":true}`, `{} {}`, `{"body_text":`} {
		r := httptest.NewRequest("POST", "/v1/drafts", bytes.NewBufferString(body))
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 400 {
			t.Fatalf("accepted %q: %d", body, w.Code)
		}
	}
	r := httptest.NewRequest("GET", "/v1/messages", nil)
	r.Header.Set("Origin", "https://example.org")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 403 {
		t.Fatal("browser origin accepted")
	}
	r = httptest.NewRequest("POST", "/v1/drafts", bytes.NewBufferString(`{}`))
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 415 {
		t.Fatal("non-JSON accepted")
	}
}
func TestPrivateUnixSocketAndActualHTTPClient(t *testing.T) {
	h, _ := apiTest(t)
	dir, e := os.MkdirTemp("/tmp", "mail-ipc-")
	if e != nil {
		t.Fatal(e)
	}
	defer os.RemoveAll(dir)
	socket := filepath.Join(dir, "mail.sock")
	listener, e := Listen(socket)
	if e != nil {
		t.Fatal(e)
	}
	srv := &http.Server{Handler: h}
	go srv.Serve(listener)
	defer srv.Close()
	info, _ := os.Stat(socket)
	if info.Mode().Perm() != 0600 {
		t.Fatalf("socket mode %v", info.Mode())
	}
	if other, e := Listen(socket); e == nil {
		other.Close()
		t.Fatal("second server replaced live socket")
	}
	client := &http.Client{Transport: &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socket)
	}}, Timeout: time.Second}
	defer client.CloseIdleConnections()
	response, e := client.Get("http://localhost/v1/health")
	if e != nil {
		t.Fatal(e)
	}
	defer response.Body.Close()
	b, _ := io.ReadAll(response.Body)
	if response.StatusCode != 200 || !bytes.Contains(b, []byte("ok")) {
		t.Fatalf("real socket: %d %s", response.StatusCode, b)
	}
}

func TestUndoDelayedSend(t *testing.T) {
	h, _ := apiTest(t)
	d := decode[backend.Message](t, request(t, h, "POST", "/v1/drafts", map[string]any{
		"account_id": "work", "to": []map[string]string{{"email": "mara@example.com"}}, "body_text": "Keep this draft",
	}, 201))
	j := decode[backend.Job](t, request(t, h, "POST", "/v1/send", map[string]any{
		"draft_id": d.ID, "idempotency_key": "undo-delayed", "undo_seconds": 60,
	}, 202))
	request(t, h, "POST", "/v1/mock/flush", map[string]any{}, 200)
	route := "/v1/outbox/" + j.ID
	queued := decode[backend.Job](t, request(t, h, "GET", route, nil, 200))
	if queued.State != "queued" || queued.UndoUntil <= time.Now().UnixMilli() {
		t.Fatalf("expected an undoable job: %+v", queued)
	}
	request(t, h, "POST", route+"/undo", map[string]any{}, 200)
	restored := decode[backend.Message](t, request(t, h, "GET", "/v1/messages/"+d.ID, nil, 200))
	if restored.Mailbox != "Drafts" || restored.BodyText != d.BodyText {
		t.Fatalf("draft not restored: %+v", restored)
	}
}

func TestTrashConversationAndUndo(t *testing.T) {
	h, _ := apiTest(t)
	request(t, h, "PATCH", "/v1/messages/seed-00", map[string]string{"mailbox": "Archive"}, 200)
	request(t, h, "PATCH", "/v1/messages/seed-01", map[string]string{"mailbox": "Trash"}, 200)
	result := decode[map[string]string](t, request(t, h, "POST", "/v1/conversations/review/trash",
		map[string]string{"account_id": "work"}, 200))
	folder := func(id string) string {
		return decode[backend.Message](t, request(t, h, "GET", "/v1/messages/"+id, nil, 200)).Mailbox
	}
	for _, id := range []string{"seed-01", "seed-02", "seed-12"} {
		if got := folder(id); got != "Trash" {
			t.Fatalf("%s in %s after trash", id, got)
		}
	}
	request(t, h, "POST", "/v1/conversation-trash/"+result["undo_token"]+"/undo", map[string]any{}, 200)
	for id, want := range map[string]string{"seed-00": "Archive", "seed-01": "Trash", "seed-02": "Inbox", "seed-12": "Sent"} {
		if got := folder(id); got != want {
			t.Fatalf("%s in %s after undo, want %s", id, got, want)
		}
	}
}

func TestTrashOriginAndPermanentDelete(t *testing.T) {
	h, _ := apiTest(t)
	const route = "/v1/messages/seed-02"
	request(t, h, "DELETE", route, nil, 409)
	request(t, h, "PATCH", route, map[string]string{"mailbox": "Archive"}, 200)
	trashed := decode[backend.Message](t, request(t, h, "PATCH", route, map[string]string{"mailbox": "Trash"}, 200))
	if trashed.TrashOrigin != "Archive" {
		t.Fatalf("trash origin = %q", trashed.TrashOrigin)
	}
	request(t, h, "PATCH", route, map[string]string{"mailbox": trashed.TrashOrigin}, 200)
	request(t, h, "PATCH", route, map[string]string{"mailbox": "Trash"}, 200)
	request(t, h, "DELETE", route, nil, 200)
	request(t, h, "GET", route, nil, 404)
}

func TestDeleteThreadLeavesOtherTrashMessages(t *testing.T) {
	h, _ := apiTest(t)
	request(t, h, "PATCH", "/v1/messages/seed-03", map[string]string{"mailbox": "Trash"}, 200)
	request(t, h, "POST", "/v1/conversations/review/trash", map[string]string{"account_id": "work"}, 200)
	const route = "/v1/messages/seed-02/delete-trash-thread"
	request(t, h, "POST", route, map[string][]string{"ids": {"seed-00", "seed-01", "seed-02", "seed-03"}}, 409)
	request(t, h, "GET", "/v1/messages/seed-00", nil, 200)
	request(t, h, "POST", route, map[string][]string{"ids": {"seed-00", "seed-01", "seed-02", "seed-12"}}, 200)
	request(t, h, "GET", "/v1/messages/seed-02", nil, 404)
	request(t, h, "GET", "/v1/messages/seed-03", nil, 200)
}

func TestSpamMoveRestoreAndPermanentDelete(t *testing.T) {
	h, _ := apiTest(t)
	move := func(id, folder string) backend.Message {
		t.Helper()
		return decode[backend.Message](t, request(t, h, "PATCH", "/v1/messages/"+id,
			map[string]string{"mailbox": folder}, 200))
	}
	if got := move("seed-02", "Spam").Mailbox; got != "Spam" {
		t.Fatalf("move to Spam returned %q", got)
	}
	if got := move("seed-02", "Inbox").Mailbox; got != "Inbox" {
		t.Fatalf("mark as no spam returned %q", got)
	}
	move("seed-02", "Spam")
	move("seed-01", "Spam")
	move("seed-03", "Spam")

	const route = "/v1/messages/seed-02/delete-spam-thread"
	request(t, h, "POST", route, map[string][]string{"ids": {"seed-02"}}, 409)
	request(t, h, "POST", route, map[string][]string{"ids": {"seed-02", "seed-03"}}, 409)
	request(t, h, "POST", "/v1/messages/seed-02/delete-trash-thread",
		map[string][]string{"ids": {"seed-02", "seed-01"}}, 409)
	request(t, h, "POST", route, map[string][]string{"ids": {"seed-02", "seed-01"}}, 200)
	for _, id := range []string{"seed-02", "seed-01"} {
		request(t, h, "GET", "/v1/messages/"+id, nil, 404)
	}
	for _, id := range []string{"seed-00", "seed-03"} {
		request(t, h, "GET", "/v1/messages/"+id, nil, 200)
	}
}

func TestRestoreThreadPreservesArchiveAndRestoresTrashMembers(t *testing.T) {
	h, _ := apiTest(t)
	move := func(id, folder string) {
		t.Helper()
		request(t, h, "PATCH", "/v1/messages/"+id, map[string]string{"mailbox": folder}, 200)
	}
	folder := func(id string) string {
		t.Helper()
		return decode[backend.Message](t, request(t, h, "GET", "/v1/messages/"+id, nil, 200)).Mailbox
	}
	move("seed-00", "Archive")
	move("seed-01", "Archive")
	move("seed-01", "Trash")
	move("seed-03", "Trash")
	request(t, h, "POST", "/v1/conversations/review/trash", map[string]string{"account_id": "work"}, 200)
	if got := folder("seed-00"); got != "Archive" {
		t.Fatalf("archived message moved to %s", got)
	}
	request(t, h, "POST", "/v1/messages/seed-02/restore-trash-thread", nil, 200)
	for id, want := range map[string]string{"seed-00": "Archive", "seed-01": "Archive", "seed-02": "Inbox", "seed-12": "Inbox", "seed-03": "Trash"} {
		if got := folder(id); got != want {
			t.Errorf("%s restored to %s, want %s", id, got, want)
		}
	}
	request(t, h, "POST", "/v1/conversations/review/trash", map[string]string{"account_id": "work"}, 200)
	request(t, h, "POST", "/v1/messages/seed-02/delete-trash-thread", map[string][]string{"ids": {"seed-02", "seed-12"}}, 200)
	for _, id := range []string{"seed-00", "seed-01"} {
		if got := folder(id); got != "Archive" {
			t.Errorf("%s in %s after deletion", id, got)
		}
	}
}

func TestImagePolicySenderOverridesGlobal(t *testing.T) {
	h, _ := apiTest(t)
	const global = "/v1/settings/image-policy"
	const message = "/v1/messages/seed-02/image-policy"
	get := func(route string) backend.ImagePolicy {
		t.Helper()
		return decode[backend.ImagePolicy](t, request(t, h, "GET", route, nil, 200))
	}
	if p := get(message); p.Policy != "ask_first" || p.Source != "default" {
		t.Fatalf("initial policy: %+v", p)
	}
	request(t, h, "PUT", global, map[string]string{"policy": "always"}, 200)
	if p := get(message); p.Policy != "always" || p.Source != "global" {
		t.Fatalf("global fallback: %+v", p)
	}
	request(t, h, "PUT", message, map[string]string{"policy": "never"}, 200)
	if p := get(message); p.Policy != "never" || p.Source != "sender" {
		t.Fatalf("sender override: %+v", p)
	}
	if p := get(global); p.Policy != "always" {
		t.Fatalf("sender update changed global policy: %+v", p)
	}
	request(t, h, "PUT", message, map[string]string{"policy": "ask_first"}, 400)
}

func TestMailboxSummaryDoesNotPreloadFullHTMLOrImageData(t *testing.T) {
	h, store := apiTest(t)
	full, err := store.Get(context.Background(), "seed-rich-text")
	if err != nil || full.BodyHTML == "" {
		t.Fatalf("missing rich fixture: %v", err)
	}
	response := request(t, h, "GET", "/v1/messages?account_id=work&mailbox=Inbox&summary=1", nil, 200)
	var page struct {
		Messages []backend.Message `json:"messages"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &page); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, message := range page.Messages {
		if message.BodyHTML != "" || len([]rune(message.BodyText)) > 512 || len(message.RemoteImages) > 0 {
			t.Fatal("list preloaded full content")
		}
		if message.ID == full.ID {
			found = message.HasHTML
		}
	}
	if !found {
		t.Fatal("HTML presence marker missing")
	}
	response = request(t, h, "GET", "/v1/conversations/"+full.ConversationID+"?account_id=work", nil, 200)
	var thread []backend.Message
	if err := json.Unmarshal(response.Body.Bytes(), &thread); err != nil {
		t.Fatal(err)
	}
	for _, message := range thread {
		if message.ID == full.ID && message.BodyHTML == full.BodyHTML {
			return
		}
	}
	t.Fatal("summary lost full content from thread API")
}

func TestImageProxyCacheOnlyAndExplicitFetchHeaders(t *testing.T) {
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
	raw := "https://images.example.test/picture.gif?token=a%20b&size=2"
	route := "/v1/messages/seed-rich-text/remote-image?url=" + url.QueryEscape(raw)
	get := func(cache, allow string, status int) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest("GET", route, nil)
		if cache != "" {
			req.Header.Set("Cache-Control", cache)
		}
		if allow != "" {
			req.Header.Set("X-Allow-Origin-Fetch", allow)
		}
		response := httptest.NewRecorder()
		h.ServeHTTP(response, req)
		if response.Code != status {
			t.Fatalf("cache=%s allow=%s: %d %s", cache, allow, response.Code, response.Body.String())
		}
		return response
	}
	get("only-if-cached", "", 504)
	get("", "", 504)                   // Without saved consent the backend denies origin access.
	get("only-if-cached", "true", 504) // The standard cache-only directive wins.
	get("", "true", 504)               // A client header cannot bypass the saved policy.

	data := []byte("GIF89a-local-image")
	sum := sha256.Sum256(data)
	digest := hex.EncodeToString(sum[:])
	if err := os.WriteFile(filepath.Join(path+".blobs", digest), data, 0600); err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Exec("INSERT INTO remote_images(message_id,url,digest,media_type) VALUES(?,?,?,?)", "seed-rich-text", raw, digest, "image/gif"); err != nil {
		t.Fatal(err)
	}
	for _, allow := range []string{"", "true"} {
		response := get("only-if-cached", allow, 200)
		if !bytes.Equal(response.Body.Bytes(), data) || response.Header().Get("Content-Type") != "image/gif" {
			t.Fatal("cached image was not returned as raw bytes")
		}
	}
}
