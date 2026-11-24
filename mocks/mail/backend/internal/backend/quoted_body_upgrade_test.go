package backend

import (
	"encoding/json"
	"reflect"
	"strings"
	"tacit.local/quotedbody"
	"testing"
)

// Persisted results from an older daemon must be upgraded without another sync.
func TestQuotedBodyUpgradeOnReopen(t *testing.T) {
	s, _, _ := openTest(t)
	m := incoming("outlook-upgrade")
	m.BodyText = "New answer"
	m.BodyHTML = `<html><body><div><p>New answer</p><div><div style="border-top:solid #E1E1E1 1pt"><p><b><span>Von:</span></b> Author<br><b>Gesendet:</b> Monday<br><b>An:</b> Recipient<br><b>Betreff:</b> Example</p></div></div><p>Unindented old mail</p><blockquote>Older mail</blockquote></div></body></html>`
	if _, err := s.CacheBatch(ctx, "work", Batch{Messages: []Message{m}}); err != nil {
		t.Fatal(err)
	}
	thread, err := s.Conversation(ctx, "work", m.ConversationID)
	if err != nil || len(thread) != 1 {
		t.Fatalf("conversation: %v", err)
	}
	id := thread[0].ID
	// Version 1 left the unindented paragraph visible.
	old := *thread[0].BodyParts
	old.Version = 1
	old.HTML = []quotedbody.Part{{Kind: quotedbody.Content, Content: m.BodyHTML}}
	encoded, err := json.Marshal(old)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.db.Exec(`UPDATE messages SET payload=json_set(payload,'$.body_parts',json(?)) WHERE id=?`, string(encoded), id); err != nil {
		t.Fatal(err)
	}
	payload := func() []byte {
		t.Helper()
		var b []byte
		if err := s.db.QueryRow(`SELECT payload FROM messages WHERE id=?`, id).Scan(&b); err != nil {
			t.Fatal(err)
		}
		return b
	}
	before := payload()
	path := s.path
	reopen := func() {
		t.Helper()
		if err := s.Close(); err != nil {
			t.Fatal(err)
		}
		s, err = Open(path)
		if err != nil {
			t.Fatal(err)
		}
	}
	reopen()
	t.Cleanup(func() { s.Close() })
	got, err := s.Get(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if got.BodyParts == nil || got.BodyParts.Version != quotedbody.Version {
		t.Fatal("reopen served an obsolete split")
	}
	found := false
	for _, part := range got.BodyParts.HTML {
		if strings.Contains(part.Content, "Unindented old mail") {
			if part.Kind != quotedbody.QuotedHistory {
				t.Fatal("unindented history is visible after restart")
			}
			found = true
		}
	}
	if !found {
		t.Fatal("historical content was lost")
	}
	after := payload()
	var a, b map[string]any
	if err = json.Unmarshal(before, &a); err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(after, &b); err != nil {
		t.Fatal(err)
	}
	delete(a, "body_parts")
	delete(b, "body_parts")
	if !reflect.DeepEqual(a, b) {
		t.Fatal("upgrade changed original message data")
	}
	thread, err = s.Conversation(ctx, "work", m.ConversationID)
	if err != nil || len(thread) != 1 || !reflect.DeepEqual(thread[0].BodyParts, got.BodyParts) {
		t.Fatal("thread did not use persisted upgraded split", err)
	}
	reopen()
	if string(payload()) != string(after) {
		t.Fatal("current split was unnecessarily rewritten")
	}
}

func TestQuotedBodyUpgradeLeavesUnversionedCurrentAndFutureUntouched(t *testing.T) {
	for _, kind := range []string{"absent", "current", "future"} {
		t.Run(kind, func(t *testing.T) {
			s, _, _ := openTest(t)
			m := incoming("upgrade-scope")
			m.BodyText = "New\n> Old"
			if _, err := s.CacheBatch(ctx, "work", Batch{Messages: []Message{m}}); err != nil {
				t.Fatal(err)
			}
			thread, err := s.Conversation(ctx, "work", m.ConversationID)
			if err != nil || len(thread) != 1 {
				t.Fatal("missing conversation", err)
			}
			id := thread[0].ID
			if kind == "absent" {
				_, err = s.db.Exec(`UPDATE messages SET payload=json_remove(payload,'$.body_parts') WHERE id=?`, id)
			} else if kind == "future" {
				_, err = s.db.Exec(`UPDATE messages SET payload=json_set(payload,'$.body_parts.version',?) WHERE id=?`, quotedbody.Version+1, id)
			}
			if err != nil {
				t.Fatal(err)
			}
			var before, after []byte
			if err = s.db.QueryRow(`SELECT payload FROM messages WHERE id=?`, id).Scan(&before); err != nil {
				t.Fatal(err)
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
			if err = s.db.QueryRow(`SELECT payload FROM messages WHERE id=?`, id).Scan(&after); err != nil {
				t.Fatal(err)
			}
			if string(before) != string(after) {
				t.Fatalf("%s payload changed during upgrade", kind)
			}
		})
	}
}
