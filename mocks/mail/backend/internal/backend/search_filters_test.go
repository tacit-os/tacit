package backend

import (
	"reflect"
	"testing"
	"time"
)

func TestSearchListFiltersKeepNewestFirst(t *testing.T) {
	s, _, _ := openTest(t)
	messages := []Message{
		{From: Address{Email: "sender@example.test"}, RemoteID: "imap:filter-old", ConversationID: "filter-old", Mailbox: "Archive", Subject: "Searchfilterneedle", Date: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), Unread: true},
		{From: Address{Email: "sender@example.test"}, RemoteID: "imap:filter-new", ConversationID: "filter-new", Mailbox: "Inbox", Subject: "Searchfilterneedle", Date: time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC), Flagged: true},
		{From: Address{Email: "sender@example.test"}, RemoteID: "imap:filter-middle", ConversationID: "filter-middle", Mailbox: "Sent", Subject: "Searchfilterneedle", Date: time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC), Unread: true, Attachments: []Attachment{{ID: "search-filter-attachment", Filename: "note.txt", MediaType: "text/plain", Data: []byte("fixture")}}},
	}
	if _, err := s.CacheBatch(ctx, "work", Batch{Cursor: "search-filters", Messages: messages}); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		filter string
		want   []string
	}{
		{"All mail", []string{"imap:filter-new", "imap:filter-middle", "imap:filter-old"}},
		{"Unread", []string{"imap:filter-middle", "imap:filter-old"}},
		{"Starred", []string{"imap:filter-new"}},
		{"With attachments", []string{"imap:filter-middle"}},
	} {
		t.Run(tc.filter, func(t *testing.T) {
			q := ViewQuery{Query: Query{Search: "Searchfilterneedle", Limit: 1}, SearchMode: true, Filter: tc.filter}
			got := []string{}
			for {
				page, err := s.ListView(ctx, q)
				if err != nil {
					t.Fatal(err)
				}
				for _, m := range page.Messages {
					got = append(got, m.RemoteID)
				}
				if len(got) >= page.Total {
					break
				}
				q.Offset = len(got)
				q.Generation = page.Generation
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("%v want %v", got, tc.want)
			}
		})
	}
}
