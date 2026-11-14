package backend

import (
	"bytes"
	"io"
	"strings"
	"testing"
	"time"
)

func TestMIMERoundTrip(t *testing.T) {
	message := Message{
		From:    Address{Name: "Élodie", Email: "elodie@example.org"},
		To:      []Address{{Email: "reader@example.org"}},
		Bcc:     []Address{{Email: "private@example.org"}},
		Subject: "Grüße", Date: time.Now(),
		MessageID: "<reply@example.org>", InReplyTo: "<root@example.org>",
		References: []string{"<root@example.org>"},
		BodyText:   "Before\nlol", BodyHTML: `<img src="cid:cat@example.org"><p>lol</p>`,
		Attachments: []Attachment{
			{ID: "cat@example.org", Filename: "Katze.gif", MediaType: "image/gif"},
			{ID: "pdf", Filename: "Notizen.pdf", MediaType: "application/pdf"},
		},
	}
	var wire bytes.Buffer
	err := WriteMIME(&wire, message, func(a Attachment) (io.ReadCloser, error) {
		return io.NopCloser(strings.NewReader(a.Filename)), nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(wire.String(), "private@example.org") {
		t.Fatal("Bcc exposed")
	}
	result, err := ReadMIME(&wire)
	if err != nil {
		t.Fatal(err)
	}
	if result.Subject != message.Subject || result.BodyText != message.BodyText ||
		result.InReplyTo != message.InReplyTo || len(result.Attachments) != 2 {
		t.Fatalf("unexpected result: %+v", result)
	}
	if !strings.Contains(result.BodyHTML, "cid:"+result.Attachments[0].ID) ||
		!strings.HasSuffix(result.BodyHTML, "<p>lol</p>") ||
		string(result.Attachments[1].Data) != "Notizen.pdf" {
		t.Fatalf("inline or attachment lost: %+v", result)
	}
}
