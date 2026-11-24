package api

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"tacit.local/mailbackend/internal/backend"
)

func TestListViewHTTPPaginationCountsAndVersion(t *testing.T) {
	h, s := apiTest(t)
	batch := backend.Batch{Cursor: "view-http"}
	for i := 0; i < 215; i++ {
		batch.Messages = append(batch.Messages, backend.Message{
			RemoteID: fmt.Sprintf("view-http-%03d", i), ConversationID: fmt.Sprintf("view-http-%03d", i/2),
			From: backend.Address{Email: "sender@example.test"}, Mailbox: "Archive",
			Subject: "Viewpaginationneedle", BodyText: strings.Repeat("ü", 1024),
			BodyHTML: "<p>" + strings.Repeat("html", 4096) + "</p>",
			Date:     time.Date(2026, 11, 20, 12, 0, i/3, i%3*1000000, time.UTC), Unread: i%2 == 0,
		})
	}
	if _, err := s.CacheBatch(context.Background(), "work", batch); err != nil {
		t.Fatal(err)
	}
	base := "/v1/messages?view=1&account_id=work&mailbox=Archive&sort=Newest+first"
	first := decode[backend.ViewPage](t, request(t, h, "GET", base+"&limit=100", nil, http.StatusOK))
	if len(first.Messages) != 100 || first.Total < 108 || first.MessageTotal < 215 || first.Generation == "" {
		t.Fatalf("page/count metadata: %+v", first)
	}
	second := decode[backend.ViewPage](t, request(t, h, "GET", base+"&limit=100&offset=100&generation="+url.QueryEscape(first.Generation), nil, http.StatusOK))
	seen := map[string]bool{}
	totalMessages := 0
	for _, page := range []backend.ViewPage{first, second} {
		for _, m := range page.Messages {
			if seen[m.ID] {
				t.Fatal("representative appeared on two pages")
			}
			seen[m.ID] = true
			totalMessages += m.FolderMessageCount
			if m.BodyHTML != "" || len([]rune(m.BodyText)) > 512 || (strings.HasPrefix(m.RemoteID, "view-http-") && !m.HasHTML) {
				t.Fatalf("full payload leaked into summary: %s", m.ID)
			}
		}
	}
	if len(seen) != first.Total || totalMessages != first.MessageTotal {
		t.Fatal("grouping/counts changed at page boundary")
	}
	counts := decode[[]backend.MailboxCount](t, request(t, h, "GET", "/v1/mailboxes/counts", nil, http.StatusOK))
	for _, count := range counts {
		if count.AccountID == "work" && count.Mailbox == "Archive" && count.Total != first.MessageTotal {
			t.Fatal("folder total counts representatives instead of messages")
		}
	}
	row := first.Messages[0]
	request(t, h, "PATCH", "/v1/messages/"+row.ID, map[string]bool{"unread": !row.Unread}, http.StatusOK)
	request(t, h, "GET", base+"&offset=100&generation="+url.QueryEscape(first.Generation), nil, http.StatusConflict)
	refreshed := decode[backend.ViewPage](t, request(t, h, "GET", base, nil, http.StatusOK))
	if refreshed.Generation == first.Generation {
		t.Fatal("mutation did not invalidate pagination version")
	}
	search := decode[backend.ViewPage](t, request(t, h, "GET", "/v1/messages?view=1&search=1&q=Viewpaginationneedle&limit=100", nil, http.StatusOK))
	if search.Total != 215 || search.MessageTotal != 215 || len(search.Messages) != 100 {
		t.Fatal("search accidentally grouped messages")
	}
	request(t, h, "GET", base+"&filter=invalid", nil, http.StatusBadRequest)
}
