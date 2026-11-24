package api

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
	"github.com/emersion/go-imap/v2/imapserver"
	"github.com/emersion/go-imap/v2/imapserver/imapmemserver"
	"github.com/emersion/go-sasl"
	"github.com/emersion/go-smtp"
	"tacit.local/mailbackend/internal/backend"
)

const fixtureEmail = "tacit@gmx.example"
const fixturePassword = "local-test-app-password"

type fixtureVault struct {
	mu      sync.Mutex
	entries map[string][]byte
}

func (v *fixtureVault) Get(_ context.Context, account string) ([]byte, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	return bytes.Clone(v.entries[account]), nil
}
func (v *fixtureVault) Put(_ context.Context, account string, secret []byte) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.entries[account] = bytes.Clone(secret)
	return nil
}
func (v *fixtureVault) Delete(_ context.Context, account string) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	delete(v.entries, account)
	return nil
}

type fixtureSMTP struct {
	conn          *smtp.Conn
	dropNextAck   *atomic.Bool
	user          *imapmemserver.User
	submissions   chan []byte
	authenticated bool
}

func (*fixtureSMTP) Reset()        {}
func (*fixtureSMTP) Logout() error { return nil }
func (s *fixtureSMTP) Mail(from string, _ *smtp.MailOptions) error {
	if !s.authenticated || from != fixtureEmail {
		return smtp.ErrAuthRequired
	}
	return nil
}
func (*fixtureSMTP) Rcpt(_ string, _ *smtp.RcptOptions) error { return nil }
func (*fixtureSMTP) AuthMechanisms() []string                 { return []string{sasl.Plain} }
func (s *fixtureSMTP) Auth(_ string) (sasl.Server, error) {
	return sasl.NewPlainServer(func(_, username, password string) error {
		if username != fixtureEmail || password != fixturePassword {
			return smtp.ErrAuthFailed
		}
		s.authenticated = true
		return nil
	}), nil
}
func (s *fixtureSMTP) Data(r io.Reader) error {
	body, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	_, err = s.user.Append("Gesendet", fixtureLiteral{bytes.NewReader(body)}, &imap.AppendOptions{Flags: []imap.Flag{imap.FlagSeen}})
	if err == nil {
		s.submissions <- body
		if s.dropNextAck.Swap(false) {
			return s.conn.Close()
		}
	}
	return err
}

type fixtureLiteral struct{ *bytes.Reader }

func (r fixtureLiteral) Size() int64 { return r.Reader.Size() }

type fixtureSearchSession struct {
	imapserver.SessionMove
	fullSearches *atomic.Int64
}

func (s fixtureSearchSession) Search(kind imapserver.NumKind, criteria *imap.SearchCriteria, options *imap.SearchOptions) (*imap.SearchData, error) {
	if criteria.Since.IsZero() {
		s.fullSearches.Add(1)
	}
	return s.SessionMove.Search(kind, criteria, options)
}

type fixtureProvider struct {
	imap, smtp   string
	roots        *x509.CertPool
	submissions  chan []byte
	dropNextAck  *atomic.Bool
	fullSearches *atomic.Int64
}

func startFixtureProvider(t *testing.T) fixtureProvider {
	t.Helper()
	// Reuse Go's loopback-name test certificate without changing system trust.
	certServer := httptest.NewTLSServer(http.NotFoundHandler())
	defer certServer.Close()
	roots := x509.NewCertPool()
	roots.AddCert(certServer.Certificate())
	config := &tls.Config{Certificates: certServer.TLS.Certificates, MinVersion: tls.VersionTLS12}
	imapListener, err := tls.Listen("tcp", "127.0.0.1:0", config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { imapListener.Close() })
	smtpListener, err := tls.Listen("tcp", "127.0.0.1:0", config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { smtpListener.Close() })
	user := imapmemserver.NewUser(fixtureEmail, fixturePassword)
	for _, name := range []string{"INBOX", "Gesendet", "Papierkorb", "Archiv", "Spam", "Bestellungen"} {
		if err := user.Create(name, nil); err != nil {
			t.Fatal(err)
		}
	}
	for _, item := range []struct{ folder, subject string }{
		{"INBOX", "Fixture inbox"}, {"Archiv", "Fixture archive"}, {"Spam", "Fixture spam"},
	} {
		body := fmt.Sprintf("From: Tester <test@example.test>\r\nTo: %s\r\nSubject: %s\r\nMessage-ID: <%s@example.test>\r\n\r\nHello from the fixture.\r\n",
			fixtureEmail, item.subject, strings.ToLower(item.folder))
		if _, err := user.Append(item.folder, fixtureLiteral{bytes.NewReader([]byte(body))}, &imap.AppendOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	imapMemory := imapmemserver.New()
	imapMemory.AddUser(user)
	fullSearches := &atomic.Int64{}
	imapServer := imapserver.New(&imapserver.Options{
		NewSession: func(*imapserver.Conn) (imapserver.Session, *imapserver.GreetingData, error) {
			session := imapMemory.NewSession()
			return fixtureSearchSession{session.(imapserver.SessionMove), fullSearches}, nil, nil
		},
		Caps: imap.CapSet{imap.CapIMAP4rev1: {}, imap.CapMove: {}, imap.CapUIDPlus: {}},
	})
	t.Cleanup(func() { imapServer.Close() })
	submissions := make(chan []byte, 10)
	dropNextAck := &atomic.Bool{}
	smtpServer := smtp.NewServer(smtp.BackendFunc(func(conn *smtp.Conn) (smtp.Session, error) {
		return &fixtureSMTP{conn: conn, user: user, submissions: submissions, dropNextAck: dropNextAck}, nil
	}))
	t.Cleanup(func() { smtpServer.Close() })
	go imapServer.Serve(imapListener)
	go smtpServer.Serve(smtpListener)
	return fixtureProvider{imapListener.Addr().String(), smtpListener.Addr().String(), roots, submissions, dropNextAck, fullSearches}
}

func (p fixtureProvider) secondClient(t *testing.T) *imapclient.Client {
	t.Helper()
	conn, err := tls.Dial("tcp", p.imap, &tls.Config{RootCAs: p.roots, MinVersion: tls.VersionTLS12})
	if err != nil {
		t.Fatal(err)
	}
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	client := imapclient.New(conn, nil)
	t.Cleanup(func() { client.Close() })
	if err := client.Login(fixtureEmail, fixturePassword).Wait(); err != nil {
		t.Fatal(err)
	}
	return client
}

type maildFixture struct {
	client *http.Client
	close  func()
}

func openMaildFixture(t *testing.T, db string, vault *fixtureVault, roots *x509.CertPool) maildFixture {
	t.Helper()
	store, err := backend.Open(db)
	if err != nil {
		t.Fatal(err)
	}
	dir, err := os.MkdirTemp("/tmp", "tacit-e2e-")
	if err != nil {
		store.Close()
		t.Fatal(err)
	}
	socket := filepath.Join(dir, "mail.sock")
	listener, err := Listen(socket)
	if err != nil {
		store.Close()
		os.RemoveAll(dir)
		t.Fatal(err)
	}
	managed := backend.NewManagedAccountsWithTLSRoots(store, vault, roots)
	mock := &backend.MockProvider{Store: store}
	service := backend.NewService(store, backend.AccountProviders{"mock": mock, backend.ManagedIMAP: managed})
	server := &http.Server{Handler: New(service, mock, managed)}
	go server.Serve(listener)
	transport := &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socket)
	}}
	var once sync.Once
	closeAll := func() {
		once.Do(func() {
			transport.CloseIdleConnections()
			server.Close()
			listener.Close()
			store.Close()
			os.RemoveAll(dir)
		})
	}
	t.Cleanup(closeAll)
	return maildFixture{&http.Client{Transport: transport, Timeout: 12 * time.Second}, closeAll}
}

func (f maildFixture) call(t *testing.T, method, route string, input, output any) {
	t.Helper()
	var body io.Reader
	if input != nil {
		raw, err := json.Marshal(input)
		if err != nil {
			t.Fatal(err)
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequest(method, "http://maild/v1/"+route, body)
	if err != nil {
		t.Fatal(err)
	}
	if input != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	response, err := f.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode/100 != 2 {
		value, _ := io.ReadAll(response.Body)
		t.Fatalf("%s %s: %d %s", method, route, response.StatusCode, value)
	}
	if output != nil {
		if err := json.NewDecoder(response.Body).Decode(output); err != nil {
			t.Fatal(err)
		}
	}
}

func TestManagedMailProviderEndToEnd(t *testing.T) {
	provider := startFixtureProvider(t)
	db := filepath.Join(t.TempDir(), "mail.sqlite")
	vault := &fixtureVault{entries: map[string][]byte{}}
	daemon := openMaildFixture(t, db, vault, provider.roots)
	settings := backend.InternetAccountSettings{Email: fixtureEmail, Password: "wrong", IMAP: provider.imap, SMTP: provider.smtp}
	var result struct {
		Account backend.Account `json:"account"`
		Error   string          `json:"error"`
	}
	daemon.call(t, "POST", "accounts/imap", settings, &result)
	if result.Error != "imap_setup_failed" || result.Account.ID != "" {
		t.Fatalf("wrong password accepted: %+v", result)
	}
	settings.Password = fixturePassword
	daemon.call(t, "POST", "accounts/imap", settings, &result)
	account := result.Account.ID
	if account == "" || !result.Account.ImportPending {
		t.Fatalf("missing connected account: %+v", result.Account)
	}
	daemon.close()
	daemon = openMaildFixture(t, db, vault, provider.roots)
	var accounts []backend.Account
	daemon.call(t, "GET", "accounts", nil, &accounts)
	if len(accounts) != 1 || !accounts[0].ImportPending {
		t.Fatalf("pending first import did not survive restart: %+v", accounts)
	}
	syncInbox := func() backend.SyncResult {
		var status backend.SyncResult
		daemon.call(t, "POST", "sync", map[string]string{"account_id": account}, &status)
		return status
	}
	findMail := func(folder, subject string) backend.Message {
		t.Helper()
		var page backend.Page
		daemon.call(t, "GET", "messages?mailbox="+folder, nil, &page)
		for _, message := range page.Messages {
			if message.Subject == subject {
				return message
			}
		}
		t.Fatalf("message %q missing in %s", subject, folder)
		return backend.Message{}
	}
	status := syncInbox()
	if status.SyncedFolders["Archive"] != "Archiv" || status.SyncedFolders["Sent"] != "Gesendet" {
		t.Fatalf("localized folders: %+v", status.SyncedFolders)
	}
	message := findMail("Inbox", "Fixture inbox")
	_ = findMail("Archive", "Fixture archive")
	_ = findMail("Spam", "Fixture spam")

	second := provider.secondClient(t)
	if _, err := second.Select("INBOX", nil).Wait(); err != nil {
		t.Fatal(err)
	}
	if err := second.Store(imap.UIDSetNum(1), &imap.StoreFlags{Op: imap.StoreFlagsAdd, Flags: []imap.Flag{imap.FlagSeen}}, nil).Close(); err != nil {
		t.Fatal(err)
	}
	syncInbox()
	if findMail("Inbox", message.Subject).Unread {
		t.Fatal("read state from second client was not imported")
	}
	daemon.call(t, "PATCH", "messages/"+message.ID, map[string]bool{"flagged": true}, nil)
	found, err := second.UIDSearch(&imap.SearchCriteria{Flag: []imap.Flag{imap.FlagFlagged}}, nil).Wait()
	if err != nil || len(found.AllUIDs()) != 1 {
		t.Fatalf("star did not reach second client: %v", err)
	}
	daemon.call(t, "PATCH", "messages/"+message.ID, map[string]string{"mailbox": "Trash"}, nil)
	if _, err := second.Select("Papierkorb", nil).Wait(); err != nil {
		t.Fatal(err)
	}
	found, err = second.UIDSearch(&imap.SearchCriteria{}, nil).Wait()
	if err != nil || len(found.AllUIDs()) != 1 {
		t.Fatalf("message did not reach server trash: %v", err)
	}
	_ = findMail("Archive", "Fixture archive")
	daemon.call(t, "DELETE", "messages/"+message.ID, nil, nil)
	syncInbox()
	var trash backend.Page
	daemon.call(t, "GET", "messages?mailbox=Trash", nil, &trash)
	found, err = second.UIDSearch(&imap.SearchCriteria{}, nil).Wait()
	if err != nil || len(found.AllUIDs()) != 1 || trash.Total != 0 {
		t.Fatal("local removal changed the provider or resurrected the removed message")
	}
	_ = findMail("Archive", "Fixture archive")

	var folders backend.IMAPFolderSettings
	daemon.call(t, "GET", "accounts/"+account+"/folders", nil, &folders)
	daemon.call(t, "PUT", "accounts/"+account+"/folders",
		map[string]any{"manual": map[string]string{"Archive": "Bestellungen"}}, &folders)
	if folders.Assigned["Archive"] != "Bestellungen" || syncInbox().SyncedFolders["Archive"] != "Bestellungen" {
		t.Fatal("manual assignment was not applied to the next sync")
	}

	var draft backend.Message
	daemon.call(t, "POST", "drafts", backend.Message{AccountID: account, Subject: "Fixture send",
		BodyText: "Only the test provider receives this.", To: []backend.Address{{Email: "receiver@example.test"}}}, &draft)
	daemon.close()
	daemon = openMaildFixture(t, db, vault, provider.roots)
	accounts = nil
	daemon.call(t, "GET", "accounts", nil, &accounts)
	if len(accounts) != 1 || accounts[0].ImportPending {
		t.Fatalf("restart did not restore account: %+v", accounts)
	}
	if findMail("Drafts", draft.Subject).ID != draft.ID {
		t.Fatal("draft identity changed after restart")
	}
	// Simulate a saved password that the provider no longer accepts.
	settings.Password = "revoked"
	settings.Username = fixtureEmail
	stale, err := json.Marshal(settings)
	if err != nil {
		t.Fatal(err)
	}
	if err := vault.Put(context.Background(), account, stale); err != nil {
		t.Fatal(err)
	}
	var reconnect map[string]any
	daemon.call(t, "POST", "accounts/"+account+"/reconnect", map[string]string{"password": "wrong"}, &reconnect)
	afterFailure, _ := vault.Get(context.Background(), account)
	if reconnect["error"] != "imap_setup_failed" || !bytes.Equal(stale, afterFailure) {
		t.Fatal("invalid replacement changed the saved credential")
	}
	reconnect = nil
	daemon.call(t, "POST", "accounts/"+account+"/reconnect", map[string]string{"password": fixturePassword}, &reconnect)
	if reconnect["ok"] != true || findMail("Drafts", draft.Subject).ID != draft.ID {
		t.Fatal("reconnect failed or replaced the existing draft")
	}
	daemon.call(t, "POST", "send", map[string]string{"draft_id": draft.ID, "idempotency_key": "fixture-send"}, nil)
	daemon.call(t, "POST", "mock/flush", map[string]any{}, nil)
	select {
	case submission := <-provider.submissions:
		if !bytes.Contains(submission, []byte("Subject: Fixture send")) {
			t.Fatal("unexpected SMTP message")
		}
	default:
		t.Fatal("SMTP provider received no message")
	}
	syncInbox()
	var sent backend.Page
	daemon.call(t, "GET", "messages?mailbox=Sent", nil, &sent)
	if len(sent.Messages) != 1 || sent.Messages[0].ID != draft.ID || !strings.HasPrefix(sent.Messages[0].RemoteID, "imap:Gesendet:") {
		t.Fatalf("Sent copy duplicated or lost identity: %+v", sent.Messages)
	}

	var secondDraft backend.Message
	daemon.call(t, "POST", "drafts", backend.Message{AccountID: account, Subject: "Fixture uncertain send",
		BodyText: "The provider will accept this, then lose the connection.", To: []backend.Address{{Email: "receiver@example.test"}}}, &secondDraft)
	var job backend.Job
	daemon.call(t, "POST", "send", map[string]string{"draft_id": secondDraft.ID, "idempotency_key": "fixture-uncertain"}, &job)
	provider.dropNextAck.Store(true)
	daemon.call(t, "POST", "mock/flush", map[string]any{}, nil)
	daemon.call(t, "GET", "outbox/"+job.ID, nil, &job)
	if job.State != "uncertain" {
		t.Fatalf("lost SMTP acknowledgement was treated as %q", job.State)
	}
	select {
	case <-provider.submissions:
	default:
		t.Fatal("the fixture did not accept the message before dropping the connection")
	}
	daemon.close()
	daemon = openMaildFixture(t, db, vault, provider.roots)
	daemon.call(t, "POST", "mock/flush", map[string]any{}, nil)
	select {
	case <-provider.submissions:
		t.Fatal("restart resent mail that may already have been delivered")
	default:
	}
}

func TestGoogleLoginRoutes(t *testing.T) {
	fixture := openMaildFixture(t, filepath.Join(t.TempDir(), "mail.sqlite"), &fixtureVault{}, nil)
	var login struct{ ID, URL, Status string }
	fixture.call(t, "POST", "oauth/google", nil, &login)
	link, err := url.Parse(login.URL)
	if err != nil || link.Host != "accounts.google.com" || login.ID == "" || login.Status != "pending" {
		t.Fatal("expected a pending browser sign-in")
	}
	var status struct{ Status string }
	fixture.call(t, "GET", "oauth/google/"+login.ID, nil, &status)
	if status.Status != "pending" {
		t.Fatalf("login status: %s", status.Status)
	}
	fixture.call(t, "DELETE", "oauth/google/"+login.ID, nil, nil)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		fixture.call(t, "GET", "oauth/google/"+login.ID, nil, &status)
		if status.Status == "failed" {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("canceled Google sign-in stayed open")
}

func TestInitialImportTracksMailboxChangesBetweenBatches(t *testing.T) {
	provider := startFixtureProvider(t)
	store, err := backend.Open(filepath.Join(t.TempDir(), "mail.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	vault := &fixtureVault{entries: map[string][]byte{}}
	manager := backend.NewManagedAccountsWithTLSRoots(store, vault, provider.roots)
	account, err := manager.Connect(context.Background(), backend.InternetAccountSettings{
		Email: fixtureEmail, Password: fixturePassword, IMAP: provider.imap, SMTP: provider.smtp,
	})
	if err != nil {
		t.Fatal(err)
	}
	service := backend.NewService(store, backend.AccountProviders{backend.ManagedIMAP: manager})
	second := provider.secondClient(t)
	appendMessage := func(folder string, i int) {
		message := fmt.Sprintf("From: Tester <test@example.test>\r\nSubject: Message %d\r\nMessage-ID: <%d@example.test>\r\n\r\nTest body\r\n", i, i)
		upload := second.Append(folder, int64(len(message)), nil)
		if _, err := io.WriteString(upload, message); err != nil {
			t.Fatal(err)
		}
		if err := upload.Close(); err != nil {
			t.Fatal(err)
		}
		if _, err := upload.Wait(); err != nil {
			t.Fatal(err)
		}
	}
	for i := 0; i < 50; i++ {
		appendMessage("INBOX", i)
	}
	if _, err := second.Select("INBOX", nil).Wait(); err != nil {
		t.Fatal(err)
	}
	var totals []int
	var firstCounts []int
	changed := false
	result, err := service.SyncWithProgress(context.Background(), account.ID, func(done, total int) {
		if done >= 0 && total > 0 {
			totals = append(totals, total)
			if len(firstCounts) < 3 {
				firstCounts = append(firstCounts, done)
			}
		}
		if changed || done < 25 {
			return
		}
		changed = true
		// One message is already cached and one is still pending.
		uids := imap.UIDSetNum(1, 51)
		if err := second.Store(uids, &imap.StoreFlags{Op: imap.StoreFlagsAdd, Flags: []imap.Flag{imap.FlagDeleted}}, nil).Close(); err != nil {
			t.Fatal(err)
		}
		if err := second.Expunge().Close(); err != nil {
			t.Fatal(err)
		}
		appendMessage("Gesendet", 90)
	})
	if err != nil || result.HasMore {
		t.Fatalf("import failed: %v", err)
	}
	if len(firstCounts) != 3 || firstCounts[0] != 0 || firstCounts[1] != 1 || firstCounts[2] != 2 {
		t.Fatalf("expected per-message progress in the first batch, got %v", firstCounts)
	}
	if len(totals) < 3 || totals[0] != 53 || totals[len(totals)-1] != 52 {
		t.Fatalf("unexpected import totals: %v", totals)
	}
	page, err := store.List(context.Background(), backend.Query{AccountID: account.ID, Mailbox: "Inbox", Limit: 100})
	if err != nil || page.Total != 49 {
		t.Fatalf("expected 49 Inbox messages, got %d (%v)", page.Total, err)
	}
	sent, err := store.List(context.Background(), backend.Query{AccountID: account.ID, Mailbox: "Sent", Limit: 100})
	if err != nil || sent.Total != 1 {
		t.Fatalf("expected the new Sent message, got %d (%v)", sent.Total, err)
	}
}

func TestInitialImportResumesOlderMailAfterOpeningMailbox(t *testing.T) {
	provider := startFixtureProvider(t)
	store, err := backend.Open(filepath.Join(t.TempDir(), "mail.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	vault := &fixtureVault{entries: map[string][]byte{}}
	manager := backend.NewManagedAccountsWithTLSRoots(store, vault, provider.roots)
	account, err := manager.Connect(context.Background(), backend.InternetAccountSettings{
		Email: fixtureEmail, Password: fixturePassword, IMAP: provider.imap, SMTP: provider.smtp,
	})
	if err != nil {
		t.Fatal(err)
	}
	client := provider.secondClient(t)
	// Give the old message a higher UID so UID ordering alone cannot pass this test.
	old := time.Now().AddDate(-2, 0, 0)
	message := "From: Tester <test@example.test>\r\nSubject: Two years old\r\nMessage-ID: <two-years@example.test>\r\n\r\nOld searchable body\r\n"
	appendOld := client.Append("INBOX", int64(len(message)), &imap.AppendOptions{Time: old})
	if _, err := io.WriteString(appendOld, message); err != nil {
		t.Fatal(err)
	}
	if err := appendOld.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := appendOld.Wait(); err != nil {
		t.Fatal(err)
	}
	newService := func() *backend.Service {
		return backend.NewService(store, backend.AccountProviders{backend.ManagedIMAP: manager})
	}
	importCtx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var recent [2]int
	var preparation []int
	before := provider.fullSearches.Load()
	ready := false
	_, err = newService().SyncWithProgress(importCtx, account.ID, func(saved, total int) {
		if saved == -3 {
			preparation = append(preparation, total)
			return
		}
		if saved == -2 {
			ready = true
			cancel()
			return
		}
		if !ready {
			recent = [2]int{saved, total}
		}
	})
	if err == nil || !ready || recent != [2]int{3, 3} {
		t.Fatalf("recent import: counts=%v ready=%t error=%v", recent, ready, err)
	}
	if !slices.Equal(preparation, []int{0, 1, 0, 2, 3, 4, 5, 7, 6, 8, 11, 11, 11, 10}) {
		t.Fatalf("unexpected preparation events: %v", preparation)
	}
	if provider.fullSearches.Load() != before {
		t.Fatal("the recent phase issued a full mailbox search before opening the inbox")
	}
	accounts, err := store.Accounts(context.Background())
	if err != nil || len(accounts) != 1 || !accounts[0].RecentImportReady || !accounts[0].ImportPending {
		t.Fatalf("recent completion was not persisted: %v, %v", accounts, err)
	}
	page, err := store.List(context.Background(), backend.Query{AccountID: account.ID, Mailbox: "Inbox", Limit: 10})
	if err != nil || page.Total != 1 {
		t.Fatalf("older mail appeared in the foreground import: total=%d error=%v", page.Total, err)
	}
	var updates [][2]int
	result, err := newService().SyncWithProgress(context.Background(), account.ID, func(saved, total int) {
		updates = append(updates, [2]int{saved, total})
	})
	if err != nil || result.HasMore || len(updates) < 3 ||
		updates[0] != [2]int{-2, 0} || updates[1] != [2]int{0, 1} || updates[len(updates)-1] != [2]int{1, 1} {
		t.Fatalf("older import: updates=%v result=%+v error=%v", updates, result, err)
	}
	page, err = store.List(context.Background(), backend.Query{AccountID: account.ID, Mailbox: "Inbox", Limit: 10})
	if err != nil || page.Total != 2 {
		t.Fatalf("older mail was not downloaded: total=%d error=%v", page.Total, err)
	}
}
