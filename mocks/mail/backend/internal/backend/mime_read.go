package backend

import (
	"bytes"
	"encoding/base64"
	"io"
	"mime"
	"mime/multipart"
	"mime/quotedprintable"
	"net/mail"
	"net/textproto"
	"strings"
)

// ReadMIME decodes a wire message. The provider supplies account, remote ID and folder.
func ReadMIME(r io.Reader) (Message, error) {
	wire, err := mail.ReadMessage(r)
	if err != nil {
		return Message{}, err
	}
	var m Message
	m.MessageID = strings.TrimSpace(wire.Header.Get("Message-ID"))
	m.InReplyTo = strings.TrimSpace(wire.Header.Get("In-Reply-To"))
	m.References = strings.Fields(wire.Header.Get("References"))
	m.Subject, err = new(mime.WordDecoder).DecodeHeader(wire.Header.Get("Subject"))
	if err != nil {
		return m, err
	}
	m.Date, _ = wire.Header.Date()
	addresses := func(field string) ([]Address, error) {
		if wire.Header.Get(field) == "" {
			return nil, nil
		}
		list, err := wire.Header.AddressList(field)
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
	var readPart func(textproto.MIMEHeader, io.Reader, int) error
	readPart = func(header textproto.MIMEHeader, source io.Reader, depth int) error {
		if depth > 32 {
			return ErrInvalid
		}
		contentType := header.Get("Content-Type")
		if contentType == "" {
			contentType = "text/plain"
		}
		kind, params, err := mime.ParseMediaType(contentType)
		if err != nil {
			return err
		}
		switch strings.ToLower(header.Get("Content-Transfer-Encoding")) {
		case "base64":
			source = base64.NewDecoder(base64.StdEncoding, source)
		case "quoted-printable":
			source = quotedprintable.NewReader(source)
		}
		if strings.HasPrefix(kind, "multipart/") {
			parts := multipart.NewReader(source, params["boundary"])
			for {
				part, err := parts.NextRawPart()
				if err == io.EOF {
					return nil
				}
				if err != nil {
					return err
				}
				err = readPart(part.Header, part, depth+1)
				part.Close()
				if err != nil {
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
		data, err := io.ReadAll(io.LimitReader(source, MaxAttachmentSize+1))
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
		file := Attachment{ID: id(), Filename: name, MediaType: contentType, Size: len(data), Data: data}
		if cid != "" {
			inline[cid] = file.ID
		}
		m.Attachments = append(m.Attachments, file)
		return nil
	}
	if err = readPart(textproto.MIMEHeader(wire.Header), wire.Body, 0); err != nil {
		return m, err
	}
	for cid, id := range inline {
		for _, quote := range []string{"\"", "'"} {
			m.BodyHTML = strings.ReplaceAll(m.BodyHTML, "cid:"+cid+quote, "cid:"+id+quote)
		}
	}
	return m, nil
}
