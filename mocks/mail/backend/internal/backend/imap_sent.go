package backend

import (
	"context"
	"io"
	"os"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

func (p *InternetProvider) syncSentCopies(ctx context.Context, client *imapclient.Client, account, folder string, renewDeadline func() error) error {
	rows, err := p.Store.db.QueryContext(ctx, `SELECT id FROM messages
		WHERE account_id=? AND mailbox='Sent' AND remote_id LIKE 'smtp:%'
		ORDER BY date LIMIT 20`, account)
	if err != nil {
		return err
	}
	ids, err := collectStrings(rows)
	if err != nil || len(ids) == 0 {
		return err
	}
	if err := renewDeadline(); err != nil {
		return err
	}
	if _, err := client.Select(folder, &imap.SelectOptions{ReadOnly: true}).Wait(); err != nil {
		return err
	}
	for _, id := range ids {
		m, err := p.Store.Get(ctx, id)
		if err != nil {
			return err
		}
		// Give servers that file SMTP submissions time to publish their own copy.
		if m.MessageID == "" || time.Since(m.Date) < 30*time.Second {
			continue
		}
		if err := renewDeadline(); err != nil {
			return err
		}
		if err := p.ensureSentCopy(ctx, client, folder, m); err != nil {
			return err
		}
	}
	return nil
}

func (p *InternetProvider) ensureSentCopy(ctx context.Context, client *imapclient.Client, folder string, m Message) error {
	found, err := client.UIDSearch(&imap.SearchCriteria{Header: []imap.SearchCriteriaHeaderField{
		{Key: "Message-ID", Value: m.MessageID},
	}}, nil).Wait()
	if err != nil || len(found.AllUIDs()) != 0 {
		return err
	}
	wire, err := os.CreateTemp("", "maild-sent-copy-*")
	if err != nil {
		return err
	}
	defer os.Remove(wire.Name())
	defer wire.Close()
	if err := p.Store.WriteMessageMIME(ctx, wire, m); err != nil {
		return err
	}
	size, err := wire.Seek(0, io.SeekCurrent)
	if err != nil {
		return err
	}
	if _, err := wire.Seek(0, io.SeekStart); err != nil {
		return err
	}
	cmd := client.Append(folder, size, &imap.AppendOptions{Flags: []imap.Flag{imap.FlagSeen}, Time: m.Date})
	_, writeErr := io.Copy(cmd, wire)
	closeErr := cmd.Close()
	if writeErr != nil {
		return writeErr
	}
	if closeErr != nil {
		return closeErr
	}
	_, err = cmd.Wait()
	return err
}
