package backend

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
	"github.com/emersion/go-smtp"
)

var ErrDeliveryUncertain = errors.New("SMTP delivery outcome unknown")

// InternetProvider imports Inbox messages over IMAPS and submits mail over SMTP with TLS.
type InternetProvider struct {
	accessToken                           string
	refreshGmailToken                     func(context.Context, string) (string, error)
	tlsRoots                              *x509.CertPool
	folderOverrides                       map[string]string
	Store                                 *Store
	Email, IMAP, SMTP, Username, Password string
}

func (p *InternetProvider) dialMail(ctx context.Context, endpoint string) (net.Conn, func(), error) {
	dialer := tls.Dialer{NetDialer: &net.Dialer{Timeout: 10 * time.Second},
		Config: &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: p.tlsRoots}}
	conn, err := dialer.DialContext(ctx, "tcp", endpoint)
	if err != nil {
		return nil, nil, err
	}
	conn.SetDeadline(time.Now().Add(20 * time.Second))
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	return conn, func() { stop(); conn.Close() }, nil
}

func (p *InternetProvider) dialSMTP(ctx context.Context) (*smtp.Client, func(), error) {
	host, port, err := net.SplitHostPort(p.SMTP)
	if err != nil {
		return nil, nil, err
	}
	if port == "587" {
		return p.dialSMTPStartTLS(ctx, host)
	}
	conn, closeConn, err := p.dialMail(ctx, p.SMTP)
	if err != nil {
		return nil, nil, err
	}
	return smtp.NewClient(conn), closeConn, nil
}

func (p *InternetProvider) dialSMTPStartTLS(ctx context.Context, host string) (*smtp.Client, func(), error) {
	dialer := net.Dialer{Timeout: 10 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", p.SMTP)
	if err != nil {
		return nil, nil, err
	}
	conn.SetDeadline(time.Now().Add(20 * time.Second))
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	closeConn := func() { stop(); conn.Close() }
	client, err := smtp.NewClientStartTLS(conn, &tls.Config{
		ServerName: host,
		MinVersion: tls.VersionTLS12,
		RootCAs:    p.tlsRoots,
	})
	if err == nil {
		// The SMTP client starts the TLS handshake with the next command.
		err = client.Hello("localhost")
	}
	if err != nil {
		closeConn()
		return nil, nil, err
	}
	return client, closeConn, nil
}

func (p *InternetProvider) Receive(ctx context.Context, account Account, cursor string) (Batch, error) {
	if account.Email != p.Email {
		return Batch{}, ErrInvalid
	}
	conn, closeConn, err := p.dialMail(ctx, p.IMAP)
	if err != nil {
		return Batch{}, fmt.Errorf("IMAP connect: %w", err)
	}
	defer closeConn()
	client := imapclient.New(conn, nil)
	if err := p.authenticateIMAP(client); err != nil {
		return Batch{}, fmt.Errorf("IMAP authenticate: %w", err)
	}
	inbox, err := client.Select("INBOX", &imap.SelectOptions{ReadOnly: true}).Wait()
	if err != nil {
		return Batch{}, fmt.Errorf("IMAP select: %w", err)
	}

	var previousValidity, last uint32
	if cursor != "" && cursor != "0" {
		if _, err := fmt.Sscanf(cursor, "%d:%d", &previousValidity, &last); err != nil {
			return Batch{}, fmt.Errorf("IMAP cursor: %w", err)
		}
	}
	if previousValidity != inbox.UIDValidity {
		last = 0
	}
	batch := Batch{Cursor: fmt.Sprintf("%d:%d", inbox.UIDValidity, last)}
	if inbox.UIDNext == 0 {
		return Batch{}, fmt.Errorf("IMAP server omitted UIDNEXT")
	}
	end := uint32(inbox.UIDNext) - 1
	if last >= end {
		return batch, nil
	}
	var rangeSet imap.UIDSet
	rangeSet.AddRange(imap.UID(last+1), imap.UID(end))
	found, err := client.UIDSearch(&imap.SearchCriteria{UID: []imap.UIDSet{rangeSet}}, nil).Wait()
	if err != nil {
		return Batch{}, fmt.Errorf("IMAP search: %w", err)
	}
	uids := found.AllUIDs()
	slices.Sort(uids)
	if len(uids) > 25 {
		uids = uids[:25]
		end = uint32(uids[len(uids)-1])
		batch.HasMore = true
	}
	if len(uids) == 0 {
		batch.Cursor = fmt.Sprintf("%d:%d", inbox.UIDValidity, end)
		return batch, nil
	}
	set := imap.UIDSetNum(uids...)
	section := &imap.FetchItemBodySection{Peek: true}
	items, err := client.Fetch(set, &imap.FetchOptions{UID: true, Flags: true, InternalDate: true,
		BodySection: []*imap.FetchItemBodySection{section}}).Collect()
	if err != nil {
		return Batch{}, fmt.Errorf("IMAP fetch: %w", err)
	}
	for _, item := range items {
		msg, err := ReadMIME(bytes.NewReader(item.FindBodySection(section)))
		if err != nil {
			return Batch{}, fmt.Errorf("decode IMAP UID %d: %w", item.UID, err)
		}
		msg.Mailbox = "Inbox"
		msg.RemoteID = fmt.Sprintf("imap:INBOX:%d:%d", inbox.UIDValidity, item.UID)
		if msg.Date.IsZero() {
			msg.Date = item.InternalDate
		}
		msg.Unread = true
		for _, flag := range item.Flags {
			if flag == imap.FlagSeen {
				msg.Unread = false
			}
			if strings.EqualFold(string(flag), "$Important") {
				msg.Important = true
			}
			if flag == imap.FlagFlagged {
				msg.Flagged = true
			}
		}
		batch.Messages = append(batch.Messages, msg)
	}
	batch.Cursor = fmt.Sprintf("%d:%d", inbox.UIDValidity, end)
	return batch, nil
}

func (p *InternetProvider) Send(ctx context.Context, account Account, msg Message, key string) (Receipt, error) {
	if account.Email != p.Email || msg.From.Email != account.Email {
		return Receipt{}, ErrInvalid
	}
	wire, err := os.CreateTemp("", "maild-smtp-*")
	if err != nil {
		return Receipt{}, err
	}
	defer os.Remove(wire.Name())
	defer wire.Close()
	if err := p.Store.WriteMessageMIME(ctx, wire, msg); err != nil {
		return Receipt{}, err
	}
	if _, err := wire.Seek(0, 0); err != nil {
		return Receipt{}, err
	}
	client, closeConn, err := p.dialSMTP(ctx)
	if err != nil {
		return Receipt{}, err
	}
	defer closeConn()
	if err := client.Auth(p.smtpAuth()); err != nil {
		return Receipt{}, err
	}
	var recipients []string
	for _, group := range [][]Address{msg.To, msg.Cc, msg.Bcc} {
		for _, address := range group {
			recipients = append(recipients, address.Email)
		}
	}
	if err := client.SendMail(msg.From.Email, recipients, wire); err != nil {
		var rejection *smtp.SMTPError
		if errors.As(err, &rejection) {
			return Receipt{}, err
		}
		return Receipt{}, fmt.Errorf("%w: %v", ErrDeliveryUncertain, err)
	}
	return Receipt{RemoteID: "smtp:" + key, SentAt: time.Now().UTC()}, nil
}

func (s *Store) ConfigureInternetAccount(ctx context.Context, email string) error {
	_, err := s.db.ExecContext(ctx, "INSERT INTO accounts(id,name,email,provider) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET email=excluded.email", "imap-"+email, email, email, "imap-smtp")
	return err
}
