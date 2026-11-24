package api

import (
	"context"
	"tacit.local/mailbackend/internal/backend"
	"testing"
)

func TestQuotedBodyAPIAndCompactList(t *testing.T) {
	h, s := apiTest(t)
	original := "<p>New</p><blockquote type='cite'>Previous message</blockquote>"
	m := backend.Message{ID: "quote-api", RemoteID: "quote-api", ConversationID: "quote-thread", From: backend.Address{Email: "sender@example.org"}, Subject: "Quote API", BodyText: "New\n> Previous message", BodyHTML: original, Mailbox: "Inbox"}
	if _, err := s.CacheBatch(context.Background(), "work", backend.Batch{Messages: []backend.Message{m}}); err != nil {
		t.Fatal(err)
	}
	messages := decode[[]backend.Message](t, request(t, h, "GET", "/v1/conversations/quote-thread?account_id=work", nil, 200))
	if len(messages) != 1 || messages[0].BodyHTML != original || messages[0].BodyParts == nil || len(messages[0].BodyParts.HTML) != 2 {
		t.Fatalf("thread split missing: %+v", messages)
	}
	id := messages[0].ID
	full := decode[backend.Message](t, request(t, h, "GET", "/v1/messages/"+id, nil, 200))
	if full.BodyParts == nil || len(full.BodyParts.Text) != 2 {
		t.Fatal("message split missing")
	}
	for _, suffix := range []string{"&summary=1", "&view=1"} {
		page := decode[backend.Page](t, request(t, h, "GET", "/v1/messages?account_id=work&mailbox=Inbox"+suffix, nil, 200))
		found := false
		for _, row := range page.Messages {
			if row.ID == id {
				found = true
				if row.BodyParts != nil || row.BodyHTML != "" {
					t.Fatal("list contains full body parts")
				}
			}
		}
		if !found {
			t.Fatal("message missing from list")
		}
	}
}
