package api

import (
	"context"
	"tacit.local/mailbackend/internal/backend"
	"testing"
	"time"
)

func TestGmailCategoryParameter(t *testing.T) {
	h, s := apiTest(t)
	m := backend.Message{RemoteID: "gmail:category-http", ConversationID: "category-http", Mailbox: "Inbox", From: backend.Address{Email: "sender@example.test"}, Subject: "Category HTTP", Date: time.Now().UTC(), GmailLabels: []string{"INBOX", "CATEGORY_PROMOTIONS"}}
	if _, err := s.CacheBatch(context.Background(), "work", backend.Batch{Cursor: "category-http", Messages: []backend.Message{m}}); err != nil {
		t.Fatal(err)
	}
	page := decode[backend.ViewPage](t, request(t, h, "GET", "/v1/messages?view=1&mailbox=Inbox&gmail_category=CATEGORY_PROMOTIONS", nil, 200))
	if page.Total != 1 || page.Messages[0].RemoteID != m.RemoteID {
		t.Fatal("category parameter not applied")
	}
	page = decode[backend.ViewPage](t, request(t, h, "GET", "/v1/messages?view=1&mailbox=Inbox&gmail_category=CATEGORY_PERSONAL", nil, 200))
	if page.Total != 0 {
		t.Fatal("non-Gmail messages included in Primary")
	}
	request(t, h, "GET", "/v1/messages?view=1&mailbox=Inbox&gmail_category=invalid", nil, 400)
}
