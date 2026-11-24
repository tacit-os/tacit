package backend

import (
	"errors"
	"strings"
	"testing"
)

func TestDraftPromptKeepsLocalNamesAndAddressesButExcludesAttachments(t *testing.T) {
	m := Message{From: Address{Name: "Ada Test", Email: "ada@example.test"},
		Subject: "private subject", BodyText: "Ada Test at ada@example.test says hello. https://example.test/secret 123456",
		BodyHTML: "<p>private html</p>", Attachments: []Attachment{{Filename: "private.pdf"}}}
	prompt := draftPrompt(DraftSuggestion{Instruction: "Please reply to Ada Test"}, []Message{m})
	for _, forbidden := range []string{m.BodyHTML, "private.pdf"} {
		if strings.Contains(prompt, forbidden) {
			t.Fatalf("prompt contains unneeded or redacted field %q", forbidden)
		}
	}
	for _, expected := range []string{"Ada Test", "ada@example.test", "says hello"} {
		if !strings.Contains(prompt, expected) {
			t.Fatalf("missing local context: %q", expected)
		}
	}
}

func TestDraftSuggestionWithoutLocalModelFailsClosed(t *testing.T) {
	_, _, service := openTest(t)
	got, err := service.SuggestDraft(ctx, DraftSuggestion{AccountID: "work", Instruction: "Write a reply"})
	if got != "" || !errors.Is(err, ErrLocalModelUnavailable) {
		t.Fatalf("unconfigured agent generated a result: %v", err)
	}
}

func TestDraftContextPrioritizesRelevantHistoryAndRespectsAccountScope(t *testing.T) {
	store, _, _ := openTest(t)
	for _, account := range []string{"first", "second"} {
		if _, err := store.db.ExecContext(ctx, "INSERT INTO accounts(id,name,email,provider) VALUES(?,?,?,?)",
			account, account, account+"@example.org", ManagedIMAP); err != nil {
			t.Fatal(err)
		}
	}
	cache := func(account, remote, mailbox, subject, address string) {
		t.Helper()
		m := incoming(remote)
		m.From = Address{Name: "Ada Test", Email: address}
		m.Subject, m.Mailbox = subject, mailbox
		if _, err := store.CacheBatch(ctx, account, Batch{Messages: []Message{m}}); err != nil {
			t.Fatal(err)
		}
	}
	cache("first", "relevant", "Archive", "Reservierung am Sonntag", "ada@example.org")
	cache("first", "different-topic", "Inbox", "Rechnung", "ADA@example.org")
	cache("first", "spam", "Spam", "Reservierung Betrug", "ada@example.org")
	cache("first", "irrelevant-person", "Inbox", "Reservierung", "another@example.org")
	cache("second", "another-account", "Sent", "Reservierung", "ada@example.org")
	cache("work", "demo", "Inbox", "Reservierung", "ada@example.org")
	request := DraftSuggestion{AccountID: "first", Subject: "Reservierung", Recipients: []string{"Ada <ada@example.org>"}}
	got, err := store.draftContext(ctx, request)
	if err != nil || len(got) != 2 || got[0].RemoteID != "relevant" || got[1].RemoteID != "different-topic" {
		t.Fatalf("single account: %v, %v", got, err)
	}
	request.AllAccounts = true
	got, err = store.draftContext(ctx, request)
	if err != nil || len(got) != 3 {
		t.Fatalf("all allowed accounts: %v, %v", got, err)
	}
	for _, item := range got {
		if item.AccountID == "work" || item.Mailbox == "Spam" {
			t.Fatal("demo or Spam mail slipped into context")
		}
	}
}
