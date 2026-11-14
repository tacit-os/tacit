package backend

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

func TestMailboxFixturesSeedHTMLAndBlobs(t *testing.T) {
	store, _, _ := openTest(t)
	for _, fixture := range []struct {
		messageID, filename, mediaType, signature string
		inline                                    bool
	}{
		{"seed-02", "Review summary.pdf", "application/pdf", "%PDF-", false},
		{"seed-04", "Train ticket.pdf", "application/pdf", "%PDF-", false},
		{"seed-rich-text", "funny-cat-52.gif", "image/gif", "GIF89a", true},
		{"seed-roastmarket", "newsletter-1.jpeg", "image/jpeg", "\xff\xd8", true},
	} {
		message, err := store.Get(ctx, fixture.messageID)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(message.BodyHTML, "data:image/") {
			t.Fatalf("%s embeds binary data in HTML", message.ID)
		}
		var attachmentID string
		for _, file := range message.Attachments {
			if file.Filename == fixture.filename {
				attachmentID = file.ID
				break
			}
		}
		if attachmentID == "" {
			t.Fatalf("%s lacks %s", message.ID, fixture.filename)
		}
		if fixture.inline && !strings.Contains(message.BodyHTML, "cid:"+attachmentID) {
			t.Fatalf("%s lacks inline reference to %s", message.ID, attachmentID)
		}
		meta, file, err := store.MessageAttachment(ctx, message.ID, attachmentID)
		if err != nil {
			t.Fatal(err)
		}
		header := make([]byte, len(fixture.signature))
		_, err = io.ReadFull(file, header)
		file.Close()
		if err != nil || meta.MediaType != fixture.mediaType || !bytes.Equal(header, []byte(fixture.signature)) {
			t.Fatalf("%s invalid blob for %s: %q %q %v", message.ID, fixture.filename, meta.MediaType, header, err)
		}
	}
}

func TestSeedUpgradePreservesEditedAndRemovedMessages(t *testing.T) {
	store, _, _ := openTest(t)
	if _, err := store.Patch(ctx, "seed-02", MessagePatch{Mailbox: "Archive"}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.db.ExecContext(ctx, "DELETE FROM messages WHERE id IN ('seed-03', 'seed-rich-text')"); err != nil {
		t.Fatal(err)
	}
	if _, err := store.db.ExecContext(ctx, "UPDATE metadata SET value='1' WHERE key='seed'"); err != nil {
		t.Fatal(err)
	}
	if err := store.Seed(ctx); err != nil {
		t.Fatal(err)
	}
	edited, err := store.Get(ctx, "seed-02")
	if err != nil || edited.Mailbox != "Archive" {
		t.Fatalf("edited fixture overwritten: %s %v", edited.Mailbox, err)
	}
	if _, err := store.Get(ctx, "seed-03"); err != ErrNotFound {
		t.Fatalf("deleted legacy fixture was recreated: %v", err)
	}
	if _, err := store.Get(ctx, "seed-rich-text"); err != nil {
		t.Fatalf("new fixture missing: %v", err)
	}
	if _, err := store.db.ExecContext(ctx, "DELETE FROM messages WHERE id='seed-rich-text'"); err != nil {
		t.Fatal(err)
	}
	if err := store.Seed(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Get(ctx, "seed-rich-text"); err != ErrNotFound {
		t.Fatalf("deleted new fixture was recreated: %v", err)
	}
}
