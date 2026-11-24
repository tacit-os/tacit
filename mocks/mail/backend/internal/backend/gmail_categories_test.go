package backend

import (
	"errors"
	"reflect"
	"testing"
	"time"
)

func TestGmailCategoryViews(t *testing.T) {
	s, _, _ := openTest(t)
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	for _, id := range []string{"category-gmail", "category-plain", "category-empty"} {
		if _, err = tx.Exec(`INSERT INTO accounts VALUES(?,?,?,'mock')`, id, id, id+"@workspace.test"); err != nil {
			t.Fatal(err)
		}
	}
	messages := []struct {
		id, thread, mailbox, label string
		day                        int
		unread                     bool
	}{
		{"uncategorized", "plain", "Inbox", "", 1, false},
		{"primary", "cross", "Inbox", "CATEGORY_PERSONAL", 4, false},
		{"promotions-old", "cross", "Inbox", "CATEGORY_PROMOTIONS", 3, true},
		{"promotions", "promo", "Inbox", "CATEGORY_PROMOTIONS", 2, false},
		{"social", "social", "Inbox", "CATEGORY_SOCIAL", 5, false},
		{"updates", "updates", "Inbox", "CATEGORY_UPDATES", 6, true},
		{"forums", "forums", "Inbox", "CATEGORY_FORUMS", 7, false},
		{"sent", "sent", "Inbox", "CATEGORY_PROMOTIONS", 8, false},
		{"archive", "archive", "Archive", "CATEGORY_PROMOTIONS", 9, false},
		{"offline", "offline", "Inbox", "CATEGORY_FORUMS", 10, false},
	}
	for _, entry := range messages {
		labels := []string{"INBOX"}
		if entry.label != "" {
			labels = append(labels, entry.label)
		}
		if entry.id == "sent" {
			labels = append(labels, "SENT")
		}
		m := Message{ID: entry.id, AccountID: "category-gmail", RemoteID: "gmail:" + entry.id, ConversationID: entry.thread, Mailbox: entry.mailbox, From: Address{Email: "sender@example.test"}, Subject: "Categoryneedle", Date: time.Date(2026, 1, entry.day, 12, 0, 0, 0, time.UTC), GmailLabels: labels, Unread: entry.unread}
		if entry.id == "offline" {
			m.RemoteID = "ignored-imap:category-gmail:gmail:offline"
		}
		if err = s.write(ctx, tx, m); err != nil {
			t.Fatal(err)
		}
	}
	if err = s.write(ctx, tx, Message{ID: "non-gmail", AccountID: "category-plain", RemoteID: "imap:plain", ConversationID: "plain", Mailbox: "Inbox", From: Address{Email: "plain@example.test"}, Subject: "Categoryneedle", Date: time.Date(2026, 1, 11, 12, 0, 0, 0, time.UTC)}); err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec(`INSERT INTO metadata VALUES('gmail-history:category-empty','1')`); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		category string
		ids      []string
		total    int
	}{
		{"", []string{"offline", "forums", "updates", "social", "primary", "promotions", "uncategorized"}, 8},
		{"CATEGORY_PERSONAL", []string{"primary", "uncategorized"}, 2},
		{"CATEGORY_PROMOTIONS", []string{"promotions-old", "promotions"}, 2},
		{"CATEGORY_SOCIAL", []string{"social"}, 1},
		{"CATEGORY_UPDATES", []string{"updates"}, 1},
		{"CATEGORY_FORUMS", []string{"offline", "forums"}, 2},
	} {
		t.Run(test.category, func(t *testing.T) {
			q := ViewQuery{Query: Query{AccountID: "category-gmail", Mailbox: "Inbox", Limit: 1}, GmailCategory: test.category}
			ids := []string{}
			for {
				page, err := s.ListView(ctx, q)
				if err != nil {
					t.Fatal(err)
				}
				if page.MessageTotal != test.total || page.Total != len(test.ids) {
					t.Fatalf("wrong counts %+v", page)
				}
				ids = append(ids, viewIDs(page)...)
				if len(ids) >= page.Total {
					break
				}
				q.Offset = len(ids)
				q.Generation = page.Generation
			}
			if !reflect.DeepEqual(ids, test.ids) {
				t.Fatalf("%v want %v", ids, test.ids)
			}
		})
	}
	filtered, err := s.ListView(ctx, ViewQuery{Query: Query{Mailbox: "Inbox"}, GmailCategory: "CATEGORY_PROMOTIONS", Filter: "Unread"})
	if err != nil || !reflect.DeepEqual(viewIDs(filtered), []string{"promotions-old"}) {
		t.Fatalf("combined filter: %+v %v", filtered, err)
	}
	primary, err := s.ListView(ctx, ViewQuery{Query: Query{Mailbox: "Inbox"}, GmailCategory: "CATEGORY_PERSONAL"})
	if err != nil || !reflect.DeepEqual(viewIDs(primary), []string{"primary", "uncategorized"}) {
		t.Fatal("non-Gmail messages leaked into Primary")
	}
	search, err := s.ListView(ctx, ViewQuery{Query: Query{Search: "Categoryneedle", Limit: 100}, SearchMode: true, GmailCategory: "CATEGORY_PROMOTIONS"})
	if err != nil || !reflect.DeepEqual(viewIDs(search), []string{"non-gmail", "offline", "archive", "sent", "forums", "updates", "social", "primary", "promotions-old", "promotions", "uncategorized"}) {
		t.Fatalf("category constrained global search: %v %v", viewIDs(search), err)
	}
	if _, err = s.ListView(ctx, ViewQuery{GmailCategory: "unknown"}); !errors.Is(err, ErrInvalid) {
		t.Fatal("invalid category accepted")
	}
	accounts, err := s.Accounts(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, account := range accounts {
		if (account.ID == "category-gmail" || account.ID == "category-empty") && account.CategoryProvider != "gmail" {
			t.Fatalf("Gmail not detected: %+v", account)
		}
		if account.ID == "category-plain" && account.CategoryProvider != "" {
			t.Fatal("non-Gmail category provider")
		}
	}
}
