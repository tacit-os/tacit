package backend

import (
	"bytes"
	"io"
	"strings"
	"testing"
	"time"
)

func TestMIMEImportanceHeader(t *testing.T) {
	for _, value := range []string{"high", "High", "normal", "low", ""} {
		t.Run(value, func(t *testing.T) {
			wire := "From: sender@example.org\r\nTo: reader@example.org\r\nImportance: " + value + "\r\n\r\nBody"
			m, err := ReadMIME(strings.NewReader(wire))
			if err != nil {
				t.Fatal(err)
			}
			if m.Importance != strings.ToLower(value) {
				t.Fatalf("importance = %q", m.Importance)
			}
		})
	}
}

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

func TestReadMIMEUsesSafeRemoteAttachmentName(t *testing.T) {
	raw := "From: sender@example.org\r\n" +
		"Content-Type: application/octet-stream\r\n" +
		"Content-Disposition: attachment; filename=\"folder/report.pdf\"\r\n\r\nattachment content"
	got, err := ReadMIME(strings.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Attachments) != 1 || got.Attachments[0].Filename != "folder_report.pdf" ||
		string(got.Attachments[0].Data) != "attachment content" {
		t.Fatal("expected safe attachment name and unchanged contents")
	}
}
