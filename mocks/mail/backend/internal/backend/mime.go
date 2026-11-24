package backend

import (
	"context"
	"io"
	"mime"
	"net/mail"
	"strings"
	"time"

	"github.com/emersion/go-message"
)

// WriteMIME serializes a queued message for a transport. Bcc belongs in the
// transport envelope and is deliberately omitted from the wire headers.
func WriteMIME(w io.Writer, m Message, open func(Attachment) (io.ReadCloser, error)) error {
	for _, value := range append([]string{m.MessageID, m.InReplyTo}, m.References...) {
		if strings.ContainsAny(value, "\r\n") {
			return ErrInvalid
		}
	}
	var header message.Header
	addresses := func(values []Address) string {
		out := make([]string, 0, len(values))
		for _, a := range values {
			out = append(out, (&mail.Address{Name: a.Name, Address: a.Email}).String())
		}
		return strings.Join(out, ", ")
	}
	headers := [][2]string{
		{"From", addresses([]Address{m.From})}, {"To", addresses(m.To)}, {"Cc", addresses(m.Cc)},
		{"Date", m.Date.Format(time.RFC1123Z)}, {"Subject", mime.QEncoding.Encode("UTF-8", m.Subject)},
		{"Message-ID", m.MessageID}, {"In-Reply-To", m.InReplyTo}, {"References", strings.Join(m.References, " ")},
		{"MIME-Version", "1.0"}, {"Content-Type", "multipart/mixed"},
	}
	for _, field := range headers {
		if strings.ContainsAny(field[1], "\r\n") {
			return ErrInvalid
		}
		if field[1] != "" {
			header.Set(field[0], field[1])
		}
	}
	mixed, err := message.CreateWriter(w, header)
	if err != nil {
		return err
	}
	writePart := func(parent *message.Writer, header message.Header, source io.Reader) error {
		header.Set("Content-Transfer-Encoding", "base64")
		part, err := parent.CreatePart(header)
		if err != nil {
			return err
		}
		if _, err := io.Copy(part, source); err != nil {
			return err
		}
		return part.Close()
	}
	nested := func(parent *message.Writer, kind string) (*message.Writer, error) {
		var header message.Header
		header.Set("Content-Type", kind)
		return parent.CreatePart(header)
	}
	attachment := func(parent *message.Writer, file Attachment, inline bool) error {
		var header message.Header
		if strings.ContainsAny(file.MediaType+file.ID, "\r\n") {
			return ErrInvalid
		}
		header.Set("Content-Type", file.MediaType)
		disposition := "attachment"
		if inline {
			disposition = "inline"
			header.Set("Content-ID", "<"+file.ID+">")
		}
		header.Set("Content-Disposition", mime.FormatMediaType(disposition, map[string]string{"filename": file.Filename}))
		reader, err := open(file)
		if err != nil {
			return err
		}
		defer reader.Close()
		return writePart(parent, header, reader)
	}
	textPart := func(parent *message.Writer, kind, content string) error {
		var header message.Header
		header.Set("Content-Type", kind+"; charset=utf-8")
		content = strings.ReplaceAll(strings.ReplaceAll(content, "\r\n", "\n"), "\n", "\r\n")
		return writePart(parent, header, strings.NewReader(content))
	}
	isInline := func(file Attachment) bool {
		return strings.Contains(m.BodyHTML, "cid:"+file.ID+"\"") || strings.Contains(m.BodyHTML, "cid:"+file.ID+"'")
	}
	if m.BodyHTML == "" {
		if err := textPart(mixed, "text/plain", m.BodyText); err != nil {
			return err
		}
	} else {
		alternatives, err := nested(mixed, "multipart/alternative")
		if err != nil {
			return err
		}
		if err = textPart(alternatives, "text/plain", m.BodyText); err != nil {
			return err
		}
		related, err := nested(alternatives, "multipart/related")
		if err != nil {
			return err
		}
		if err = textPart(related, "text/html", m.BodyHTML); err != nil {
			return err
		}
		for _, file := range m.Attachments {
			if isInline(file) {
				if err = attachment(related, file, true); err != nil {
					return err
				}
			}
		}
		if err = related.Close(); err != nil {
			return err
		}
		if err = alternatives.Close(); err != nil {
			return err
		}
	}
	for _, file := range m.Attachments {
		if !isInline(file) {
			if err := attachment(mixed, file, false); err != nil {
				return err
			}
		}
	}
	return mixed.Close()
}

// WriteMessageMIME resolves attachment references from the local blob store.
func (s *Store) WriteMessageMIME(ctx context.Context, w io.Writer, m Message) error {
	return WriteMIME(w, m, func(a Attachment) (io.ReadCloser, error) {
		_, file, err := s.OpenAttachment(ctx, m.AccountID, a.ID)
		if err != nil {
			return nil, err
		}
		return file, nil
	})
}
