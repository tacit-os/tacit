package backend

import (
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func viewIDs(p ViewPage) []string {
	ids := []string{}
	for _, m := range p.Messages {
		ids = append(ids, m.ID)
	}
	return ids
}

// Embed authored expectations so changing the contract invalidates Go's test
// cache. The native integration suite reads this same file, without a copy.
//
//go:embed testdata/list-contract.json
var listContractJSON []byte

// Expectations are authored data, not the output of another query engine.
type listContract struct {
	Accounts []Account `json:"accounts"`
	Messages []Message `json:"messages"`
	Cases    []struct {
		Name         string `json:"name"`
		Account      string `json:"account"`
		Folder       string `json:"folder"`
		Filter       string `json:"filter"`
		Sort         string `json:"sort"`
		MessageTotal int    `json:"message_total"`
		Rows         []struct {
			ID           string `json:"id"`
			Count        int    `json:"count"`
			Starred      bool   `json:"starred"`
			OtherStarred bool   `json:"other_starred"`
		} `json:"rows"`
	} `json:"cases"`
	Searches []struct {
		Term string   `json:"term"`
		IDs  []string `json:"ids"`
	} `json:"searches"`
	Counts []MailboxCount `json:"counts"`
}

func contractStore(t *testing.T) (*Store, listContract) {
	t.Helper()
	var fixture listContract
	if err := json.Unmarshal(listContractJSON, &fixture); err != nil {
		t.Fatal(err)
	}
	s, err := Open(filepath.Join(t.TempDir(), "mail.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	for _, account := range fixture.Accounts {
		if _, err = tx.Exec(`INSERT INTO accounts VALUES(?,?,?,?)`, account.ID, account.Name, account.Email, account.Provider); err != nil {
			t.Fatal(err)
		}
	}
	for _, message := range fixture.Messages {
		for i := range message.Attachments {
			message.Attachments[i].Data = []byte("file")
		}
		if err = s.write(ctx, tx, message); err != nil {
			t.Fatal(err)
		}
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	return s, fixture
}
func TestListViewExplicitContract(t *testing.T) {
	s, fixture := contractStore(t)
	for _, test := range fixture.Cases {
		for _, limit := range []int{1, 2, 7, 100} {
			t.Run(fmt.Sprintf("%s/page-%d", test.Name, limit), func(t *testing.T) {
				q := ViewQuery{Query: Query{AccountID: test.Account, Mailbox: test.Folder, Limit: limit}, Filter: test.Filter, Sort: test.Sort}
				got := []ViewMessage{}
				for {
					page, err := s.ListView(ctx, q)
					if err != nil {
						t.Fatal(err)
					}
					if page.Total != len(test.Rows) || page.MessageTotal != test.MessageTotal {
						t.Fatalf("counts: rows=%d messages=%d, want %d/%d", page.Total, page.MessageTotal, len(test.Rows), test.MessageTotal)
					}
					got = append(got, page.Messages...)
					if len(got) >= page.Total {
						break
					}
					if len(page.Messages) == 0 {
						t.Fatal("pagination made no progress")
					}
					q.Offset = len(got)
					q.Generation = page.Generation
				}
				if len(got) != len(test.Rows) {
					t.Fatal("missing/duplicate representatives")
				}
				for i, m := range got {
					want := test.Rows[i]
					if m.ID != want.ID || m.FolderMessageCount != want.Count || m.FolderStarred != want.Starred || m.FolderOtherStarred != want.OtherStarred {
						t.Fatalf("row %d: got %s/%d/%t/%t, want %+v", i, m.ID, m.FolderMessageCount, m.FolderStarred, m.FolderOtherStarred, want)
					}
					if m.BodyHTML != "" || len([]rune(m.BodyText)) > 512 || len(m.RemoteImages) > 0 {
						t.Fatal("full content in list response")
					}
				}
			})
		}
	}
	counts, err := s.MailboxCounts(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(counts, fixture.Counts) {
		// SQL order is not part of the counter contract; keys and values are.
		actual := map[string]MailboxCount{}
		for _, count := range counts {
			actual[count.AccountID+":"+count.Mailbox] = count
		}
		if len(actual) != len(fixture.Counts) {
			t.Fatal("extra/missing folder counters")
		}
		for _, want := range fixture.Counts {
			if actual[want.AccountID+":"+want.Mailbox] != want {
				t.Fatalf("counter %+v", want)
			}
		}
	}
}
func TestListViewRejectsMixedVersionsAndTracksMutations(t *testing.T) {
	s, _, _ := openTest(t)
	q := ViewQuery{Query: Query{Mailbox: "Inbox", Limit: 1}}
	first, err := s.ListView(ctx, q)
	if err != nil || first.Total < 2 {
		t.Fatalf("%+v %v", first, err)
	}
	old := first.Messages[0]
	unread := !old.Unread
	if _, err = s.Patch(ctx, old.ID, MessagePatch{Unread: &unread, Mailbox: "Archive"}); err != nil {
		t.Fatal(err)
	}
	q.Offset = 1
	q.Generation = first.Generation
	if _, err = s.ListView(ctx, q); !errors.Is(err, ErrConflict) {
		t.Fatalf("mixed pages accepted: %v", err)
	}
	q.Offset = 0
	q.Generation = ""
	refreshed, err := s.ListView(ctx, q)
	if err != nil || refreshed.Generation == first.Generation || refreshed.Messages[0].ID == old.ID {
		t.Fatalf("stale projection: %+v %v", refreshed, err)
	}
	q.Mailbox = "Archive"
	q.Limit = 100
	archived, err := s.ListView(ctx, q)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, m := range archived.Messages {
		if m.ID == old.ID {
			found = true
			if m.Unread != unread {
				t.Fatal("stale unread")
			}
		}
	}
	if !found {
		t.Fatal("moved row missing")
	}
	if _, err = s.db.Exec(`DELETE FROM messages WHERE id=?`, old.ID); err != nil {
		t.Fatal(err)
	}
	archived, err = s.ListView(ctx, q)
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range archived.Messages {
		if m.ID == old.ID {
			t.Fatal("deleted row retained")
		}
	}
}
func TestListViewSearchAndSummarySurviveReopen(t *testing.T) {
	s, fixture := contractStore(t)
	path := s.path
	s.Close()
	reopened, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	for _, test := range fixture.Searches {
		page, err := reopened.ListView(ctx, ViewQuery{Query: Query{Search: test.Term, Limit: 100}, SearchMode: true})
		if err != nil || !reflect.DeepEqual(viewIDs(page), test.IDs) {
			t.Fatalf("search %q: %v want %v: %v", test.Term, viewIDs(page), test.IDs, err)
		}
		for _, m := range page.Messages {
			if m.ID == "query-a-old" && (!m.HasHTML || len([]rune(m.BodyText)) != 512) {
				t.Fatal("HTML marker/Unicode preview lost")
			}
			if m.ID == "query-a-inbox-b" && (len(m.Attachments) != 1 || !m.Attachments[0].Inline) {
				t.Fatal("inline attachment marker lost")
			}
		}
	}
	for _, q := range []ViewQuery{{Query: Query{Limit: 101}}, {Query: Query{Offset: -1}}, {Filter: "bogus"}, {Sort: "bogus"}} {
		if _, err = reopened.ListView(ctx, q); !errors.Is(err, ErrInvalid) {
			t.Fatalf("invalid query accepted: %+v %v", q, err)
		}
	}
}
func TestListViewSenderUsesClientLocale(t *testing.T) {
	s, _, _ := openTest(t)
	batch := Batch{Cursor: "view-locale"}
	for i, name := range []string{"Zoe", "Åke", "Änne"} {
		m := incoming(fmt.Sprintf("view-locale-%d", i))
		m.ConversationID = m.RemoteID
		m.From.Name = name
		m.Mailbox = "Spam"
		batch.Messages = append(batch.Messages, m)
	}
	if _, err := s.CacheBatch(ctx, "work", batch); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		locale string
		want   []string
	}{
		{"de", []string{"Åke", "Änne", "Zoe"}},
		{"sv", []string{"Zoe", "Åke", "Änne"}},
	} {
		p, err := s.ListView(ctx, ViewQuery{Query: Query{AccountID: "work", Mailbox: "Spam"}, Sort: "Sender", Locale: test.locale})
		if err != nil {
			t.Fatal(err)
		}
		names := []string{}
		for _, m := range p.Messages {
			if strings.HasPrefix(m.RemoteID, "view-locale-") {
				names = append(names, m.From.Name)
			}
		}
		if !reflect.DeepEqual(names, test.want) {
			t.Fatalf("locale %s: got %v want %v", test.locale, names, test.want)
		}
	}
}

func TestListViewBackfillsExistingCacheAndChecksSelection(t *testing.T) {
	s, fixture := contractStore(t)
	read := false
	if _, err := s.Patch(ctx, "query-a-old", MessagePatch{Unread: &read}); err != nil {
		t.Fatal(err)
	}
	// Simulate a pre-upgrade cache. The source messages/attachments are untouched.
	if _, err := s.db.Exec(`DROP TRIGGER message_list_insert; DROP TRIGGER message_list_update;
        DROP TRIGGER message_list_delete; DROP TABLE message_list; DROP TABLE message_list_generation;`); err != nil {
		t.Fatal(err)
	}
	path := s.path
	s.Close()
	upgraded, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer upgraded.Close()
	q := ViewQuery{Query: Query{AccountID: "query-a", Mailbox: "Inbox", Limit: 100}, SelectedID: "query-a-old"}
	p, err := upgraded.ListView(ctx, q)
	if err != nil || p.MissingID != "" {
		t.Fatalf("existing older thread message discarded: %+v %v", p, err)
	}
	want := fixture.Cases[0].Rows
	for i, m := range p.Messages {
		if m.ID != want[i].ID {
			t.Fatal("upgrade changed cached list")
		}
	}
	if len(p.Messages) != len(want) {
		t.Fatal("upgrade lost cached messages")
	}
	if _, err = upgraded.db.Exec(`DELETE FROM messages WHERE id='query-a-old'`); err != nil {
		t.Fatal(err)
	}
	p, err = upgraded.ListView(ctx, q)
	if err != nil || p.MissingID != "query-a-old" {
		t.Fatalf("deleted selection retained: %+v %v", p, err)
	}
}

func TestListViewGmailLabelStarWithoutFlag(t *testing.T) {
	s, _ := contractStore(t)
	message := incoming("label-star")
	message.ID = "query-label-only"
	message.AccountID = "query-a"
	message.Mailbox = "Spam"
	message.Flagged = false
	message.GmailLabels = []string{"STARRED"}
	message.Attachments = nil
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err = s.write(ctx, tx, message); err != nil {
		tx.Rollback()
		t.Fatal(err)
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		folder, filter string
		ids            []string
	}{
		{"Spam", "Starred", []string{"query-label-only", "query-a-spam-old"}},
		{"Starred", "All mail", []string{"query-label-only", "query-a-archive-new", "query-a-old", "query-a-spam-old"}},
	} {
		page, err := s.ListView(ctx, ViewQuery{Query: Query{AccountID: "query-a", Mailbox: test.folder}, Filter: test.filter})
		if err != nil || !reflect.DeepEqual(viewIDs(page), test.ids) {
			t.Fatalf("label-only star: %v want %v: %v", viewIDs(page), test.ids, err)
		}
		if !page.Messages[0].FolderStarred {
			t.Fatal("Gmail star label ignored")
		}
	}
}
