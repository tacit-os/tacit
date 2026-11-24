package backend

import (
	"encoding/json"
	"reflect"
	"tacit.local/quotedbody"
	"testing"
)

func TestQuotedBodyStoredWithOriginalAndSearchable(t *testing.T) {
	s, _, _ := openTest(t)
	m := incoming("quoted-body")
	m.BodyText = "New answer\n\nOn Tuesday, Alex wrote:\n> HistoricalNeedle"
	m.BodyHTML = "<style>p{color:red}</style><p>New answer</p><blockquote type='cite'>HistoricalNeedle<img src='cid:old'></blockquote>"
	if _, err := s.CacheBatch(ctx, "work", Batch{Messages: []Message{m}}); err != nil {
		t.Fatal(err)
	}
	thread, err := s.Conversation(ctx, "work", m.ConversationID)
	if err != nil || len(thread) != 1 {
		t.Fatalf("thread: %v %v", thread, err)
	}
	got := thread[0]
	if got.BodyText != m.BodyText || got.BodyHTML != m.BodyHTML {
		t.Fatal("original body changed")
	}
	if got.BodyParts == nil || len(got.BodyParts.Text) != 2 || len(got.BodyParts.HTML) != 2 {
		t.Fatalf("missing split: %+v", got.BodyParts)
	}
	if got.BodyParts.HTML[1].Kind != quotedbody.QuotedHistory {
		t.Fatal("wrong part kind")
	}
	var stored []byte
	if err = s.db.QueryRow("SELECT payload FROM messages WHERE id=?", got.ID).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	var persisted Message
	if err = json.Unmarshal(stored, &persisted); err != nil || !reflect.DeepEqual(got.BodyParts, persisted.BodyParts) {
		t.Fatal("split not persisted", err)
	}
	path := s.path
	if err = s.Close(); err != nil {
		t.Fatal(err)
	}
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	reopened, err := s.Get(ctx, got.ID)
	if err != nil || !reflect.DeepEqual(reopened.BodyParts, got.BodyParts) {
		t.Fatal("split lost after restart", err)
	}
	page, err := s.List(ctx, Query{Search: "HistoricalNeedle"})
	if err != nil || page.Total != 1 {
		t.Fatal("quoted text no longer searchable", err)
	}
	unread := false
	updated, err := s.Patch(ctx, got.ID, MessagePatch{Unread: &unread})
	if err != nil || !reflect.DeepEqual(updated.BodyParts, got.BodyParts) {
		t.Fatal("flag update changed split", err)
	}
	m.BodyText = "Replacement without quotes"
	m.BodyHTML = "<p>Replacement</p>"
	if _, err = s.CacheBatch(ctx, "work", Batch{Messages: []Message{m}}); err != nil {
		t.Fatal(err)
	}
	fresh, err := s.Get(ctx, got.ID)
	if err != nil || fresh.BodyParts == nil || len(fresh.BodyParts.HTML) != 0 || len(fresh.BodyParts.Text) != 0 {
		t.Fatal("body update retained stale quote parts", err)
	}
}
func TestQuotedBodyVersionInvalidationAndDraftIsolation(t *testing.T) {
	s, _, _ := openTest(t)
	m := incoming("quoted-version")
	m.BodyText = "New\n> Old"
	if _, err := s.CacheBatch(ctx, "work", Batch{Messages: []Message{m}}); err != nil {
		t.Fatal(err)
	}
	thread, _ := s.Conversation(ctx, "work", m.ConversationID)
	got := thread[0]
	_, err := s.db.Exec("UPDATE messages SET payload=json_set(payload,'$.body_parts.version',0) WHERE id=?", got.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.Patch(ctx, got.ID, MessagePatch{Mailbox: "Archive"}); err != nil {
		t.Fatal(err)
	}
	got, _ = s.Get(ctx, got.ID)
	if got.BodyParts.Version != quotedbody.Version {
		t.Fatal("outdated split was reused")
	}
	d := draft(t, s, "Quoted draft")
	d.BodyText = "New\n> Editable quote"
	d.BodyHTML = "New<blockquote>Editable quote</blockquote>"
	d.BodyParts = got.BodyParts
	saved, err := s.SaveDraft(ctx, d)
	if err != nil {
		t.Fatal(err)
	}
	stored, err := s.Get(ctx, saved.ID)
	if err != nil || stored.BodyParts != nil {
		t.Fatal("draft acquired read-only body parts", err)
	}
}

func TestQuotedBodyLegacyReadRemainsUnchanged(t *testing.T) {
	s, _, _ := openTest(t)
	m := incoming("legacy-quote")
	m.BodyText = "New\n> Old"
	if _, err := s.CacheBatch(ctx, "work", Batch{Messages: []Message{m}}); err != nil {
		t.Fatal(err)
	}
	thread, _ := s.Conversation(ctx, "work", m.ConversationID)
	id := thread[0].ID
	if _, err := s.db.Exec("UPDATE messages SET payload=json_remove(payload,'$.body_parts') WHERE id=?", id); err != nil {
		t.Fatal(err)
	}
	got, err := s.Get(ctx, id)
	if err != nil || got.BodyParts != nil || got.BodyText != m.BodyText {
		t.Fatal("legacy message read changed", err)
	}
}

func TestQuotedBodySourceSeparatesTextAndHTML(t *testing.T) {
	s, _, _ := openTest(t)
	m := incoming("body-boundary")
	m.BodyText = "New\n> Old\x00"
	m.BodyHTML = "tail"
	if _, err := s.CacheBatch(ctx, "work", Batch{Messages: []Message{m}}); err != nil {
		t.Fatal(err)
	}
	thread, _ := s.Conversation(ctx, "work", m.ConversationID)
	previous := thread[0].BodyParts.Source
	m.BodyText = "New\n> Old"
	m.BodyHTML = "\x00tail"
	if _, err := s.CacheBatch(ctx, "work", Batch{Messages: []Message{m}}); err != nil {
		t.Fatal(err)
	}
	fresh, _ := s.Get(ctx, thread[0].ID)
	if fresh.BodyParts.Source == previous {
		t.Fatal("distinct text/HTML boundaries reused the split")
	}
}
