package backend

import (
	"bytes"
	"io"
	"mime"
	"strings"

	"github.com/emersion/go-message"
	_ "github.com/emersion/go-message/charset"
	"github.com/emersion/go-message/mail"
)

// ReadMIME decodes a wire message. The provider supplies account, remote ID and folder.
func ReadMIME(r io.Reader) (Message, error) {
	wire, err := message.Read(r)
	if err != nil {
		return Message{}, err
	}
	var m Message
	m.Importance = strings.ToLower(strings.TrimSpace(wire.Header.Get("Importance")))
	autoSubmitted := strings.TrimSpace(wire.Header.Get("Auto-Submitted"))
	m.Automated = wire.Header.Get("List-Id") != "" ||
		(autoSubmitted != "" && !strings.EqualFold(autoSubmitted, "no"))
	m.MessageID = strings.TrimSpace(wire.Header.Get("Message-ID"))
	m.InReplyTo = strings.TrimSpace(wire.Header.Get("In-Reply-To"))
	m.References = strings.Fields(wire.Header.Get("References"))
	header := mail.Header{Header: wire.Header}
	m.Subject, err = header.Subject()
	if err != nil {
		return m, err
	}
	m.Date, _ = header.Date()
	addresses := func(field string) ([]Address, error) {
		if wire.Header.Get(field) == "" {
			return nil, nil
		}
		list, err := header.AddressList(field)
		var result []Address
		for _, address := range list {
			result = append(result, Address{Name: address.Name, Email: address.Address})
		}
		return result, err
	}
	from, err := addresses("From")
	if err != nil || len(from) != 1 {
		return m, ErrInvalid
	}
	m.From = from[0]
	if m.To, err = addresses("To"); err != nil {
		return m, err
	}
	if m.Cc, err = addresses("Cc"); err != nil {
		return m, err
	}
	if m.Bcc, err = addresses("Bcc"); err != nil {
		return m, err
	}
	inline := map[string]string{}
	var readPart func(*message.Entity, int) error
	readPart = func(part *message.Entity, depth int) error {
		if depth > 32 {
			return ErrInvalid
		}
		header := part.Header
		contentType := header.Get("Content-Type")
		if contentType == "" {
			contentType = "text/plain"
		}
		kind, params, err := header.ContentType()
		if err != nil {
			return err
		}
		if parts := part.MultipartReader(); parts != nil {
			defer parts.Close()
			for {
				child, err := parts.NextPart()
				if err == io.EOF {
					return nil
				}
				if err != nil {
					return err
				}
				if err := readPart(child, depth+1); err != nil {
					return err
				}
			}
		}
		disposition, values, _ := mime.ParseMediaType(header.Get("Content-Disposition"))
		name := values["filename"]
		if name == "" {
			name = params["name"]
		}
		cid := strings.Trim(header.Get("Content-ID"), " <>")
		data, err := io.ReadAll(io.LimitReader(part.Body, MaxAttachmentSize+1))
		if err != nil {
			return err
		}
		if int64(len(data)) > MaxAttachmentSize {
			return ErrTooLarge
		}
		if name == "" && disposition != "attachment" && (kind == "text/plain" || kind == "text/html") {
			text := string(bytes.ReplaceAll(data, []byte("\r\n"), []byte("\n")))
			if kind == "text/html" {
				m.BodyHTML = text
			} else {
				m.BodyText = text
			}
			return nil
		}
		if name == "" {
			name = "attachment"
		}
		// A remote filename is only a label. Path separators and control
		// characters must not make an otherwise readable mail fail to import.
		name = strings.Map(func(r rune) rune {
			if r == '/' || r == '\\' || r < 32 || r == 127 {
				return '_'
			}
			return r
		}, name)
		if !validAttachment(name, contentType) {
			name = "attachment"
			contentType = mime.FormatMediaType(kind, nil)
			if !validAttachment(name, contentType) {
				contentType = "application/octet-stream"
			}
		}
		file := Attachment{ID: id(), Filename: name, MediaType: contentType, Size: len(data), Data: data}
		if cid != "" {
			inline[cid] = file.ID
		}
		m.Attachments = append(m.Attachments, file)
		return nil
	}
	if err = readPart(wire, 0); err != nil {
		return m, err
	}
	for cid, id := range inline {
		for _, quote := range []string{"\"", "'"} {
			m.BodyHTML = strings.ReplaceAll(m.BodyHTML, "cid:"+cid+quote, "cid:"+id+quote)
		}
	}
	return m, nil
}
