package backend

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

type imapFolder struct{ local, remote string }

var configurableIMAPRoles = []string{"Archive", "Spam", "Sent", "Trash"}

func selectableIMAPFolder(mailbox *imap.ListData) bool {
	return mailbox.Mailbox != "" && !strings.EqualFold(mailbox.Mailbox, "INBOX") &&
		!slices.Contains(mailbox.Attrs, imap.MailboxAttrNoSelect) &&
		!slices.Contains(mailbox.Attrs, imap.MailboxAttrNonExistent) &&
		!slices.Contains(mailbox.Attrs, imap.MailboxAttrAll) &&
		!slices.Contains(mailbox.Attrs, imap.MailboxAttrDrafts)
}

func resolveIMAPFolders(listed []*imap.ListData, overrides ...map[string]string) []imapFolder {
	folders := []imapFolder{{"Inbox", "INBOX"}}
	seen := map[string]bool{"INBOX": true}
	var manual map[string]string
	if len(overrides) > 0 {
		manual = overrides[0]
	}
	for _, role := range configurableIMAPRoles {
		target := manual[role]
		for _, box := range listed {
			if target != "" && !seen[target] && box.Mailbox == target && selectableIMAPFolder(box) {
				seen[target] = true
				folders = append(folders, imapFolder{role, target})
				break
			}
		}
	}
	for _, role := range []struct {
		local string
		attr  imap.MailboxAttr
		names []string
	}{
		{"Archive", imap.MailboxAttrArchive, []string{"archive", "archiv"}},
		{"Spam", imap.MailboxAttrJunk, []string{"spam", "junk"}},
		{"Sent", imap.MailboxAttrSent, []string{"sent", "sent items", "sent messages", "gesendet"}},
		{"Trash", imap.MailboxAttrTrash, []string{"trash", "deleted items", "papierkorb"}},
	} {
		if manual[role.local] != "" {
			continue
		}
		var advertised, named []string
		for _, mailbox := range listed {
			if seen[mailbox.Mailbox] || !selectableIMAPFolder(mailbox) {
				continue
			}
			if slices.Contains(mailbox.Attrs, role.attr) {
				if !slices.Contains(advertised, mailbox.Mailbox) {
					advertised = append(advertised, mailbox.Mailbox)
				}
			}
			if slices.Contains(role.names, strings.ToLower(mailbox.Mailbox)) && !slices.Contains(named, mailbox.Mailbox) {
				named = append(named, mailbox.Mailbox)
			}
		}
		candidates := advertised
		if len(candidates) == 0 {
			candidates = named
		}
		if len(candidates) == 1 {
			seen[candidates[0]] = true
			folders = append(folders, imapFolder{role.local, candidates[0]})
		}
	}
	return folders
}

func listIMAPCatalog(client *imapclient.Client) ([]*imap.ListData, error) {
	options := &imap.ListOptions{ReturnSpecialUse: client.Caps().Has(imap.CapSpecialUse)}
	return client.List("", "*", options).Collect()
}

func listIMAPFolders(client *imapclient.Client, manual map[string]string, includeAll bool) ([]imapFolder, error) {
	listed, err := listIMAPCatalog(client)
	if err != nil {
		return nil, err
	}
	folders := resolveIMAPFolders(listed, manual)
	if includeAll && !slices.ContainsFunc(folders, func(folder imapFolder) bool { return folder.local == "Archive" }) {
		for _, box := range listed {
			if slices.Contains(box.Attrs, imap.MailboxAttrAll) && !slices.Contains(box.Attrs, imap.MailboxAttrNoSelect) &&
				!slices.Contains(box.Attrs, imap.MailboxAttrNonExistent) {
				folders = append(folders, imapFolder{local: "Archive", remote: box.Mailbox})
				break
			}
		}
	}
	return folders, nil
}

func remoteIMAPFolder(client *imapclient.Client, local string, manual map[string]string) (string, error) {
	if local == "Inbox" {
		return "INBOX", nil
	}
	folders, err := listIMAPFolders(client, manual, false)
	if err != nil {
		return "", err
	}
	for _, folder := range folders {
		if folder.local == local {
			return folder.remote, nil
		}
	}
	return "", fmt.Errorf("IMAP server has no known %s mailbox", local)
}

const imapFolderSettingsKey = "imap-folder-settings:"

func loadIMAPFolderSettings(ctx context.Context, db interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}, account string) (map[string]string, error) {
	var raw string
	err := db.QueryRowContext(ctx, "SELECT value FROM metadata WHERE key=?", imapFolderSettingsKey+account).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var mapping map[string]string
	err = json.Unmarshal([]byte(raw), &mapping)
	return mapping, err
}

type IMAPFolderSettings struct {
	Available []string          `json:"available"`
	Assigned  map[string]string `json:"assigned"`
	Manual    map[string]string `json:"manual"`
}

// FolderSettings lists selectable server folders. A non-nil update replaces
// the account's explicit choices after verifying them against the live catalog.
func (s *Service) FolderSettings(ctx context.Context, id string, update map[string]string) (IMAPFolderSettings, error) {
	s.syncMu.Lock()
	defer s.syncMu.Unlock()
	account, err := s.Store.Account(ctx, id)
	if err != nil {
		return IMAPFolderSettings{}, err
	}
	internet := s.internetTransport(account)
	if account.Provider == ManagedIMAP && s.Store.remoteTransports != nil {
		if managed, ok := s.Store.remoteTransports[ManagedIMAP].(*ManagedAccounts); ok {
			internet, err = managed.transport(ctx, account)
			if err != nil {
				return IMAPFolderSettings{}, err
			}
		}
	}
	if internet == nil {
		return IMAPFolderSettings{}, ErrInvalid
	}
	manual, err := loadIMAPFolderSettings(ctx, s.Store.db, id)
	if err != nil {
		return IMAPFolderSettings{}, err
	}
	conn, closeConn, err := internet.dialMail(ctx, internet.IMAP)
	if err != nil {
		return IMAPFolderSettings{}, err
	}
	defer closeConn()
	client := imapclient.New(conn, nil)
	if err := internet.authenticateIMAP(client); err != nil {
		return IMAPFolderSettings{}, err
	}
	boxes, err := listIMAPCatalog(client)
	if err != nil {
		return IMAPFolderSettings{}, err
	}
	available := []string{}
	for _, box := range boxes {
		if selectableIMAPFolder(box) && !slices.Contains(available, box.Mailbox) {
			available = append(available, box.Mailbox)
		}
	}
	slices.Sort(available)
	if update != nil {
		used := map[string]bool{}
		for role, box := range update {
			if !slices.Contains(configurableIMAPRoles, role) || !slices.Contains(available, box) || used[box] {
				return IMAPFolderSettings{}, ErrInvalid
			}
			used[box] = true
		}
		raw, err := json.Marshal(update)
		if err != nil {
			return IMAPFolderSettings{}, err
		}
		if _, err := s.Store.db.ExecContext(ctx, `INSERT INTO metadata(key,value) VALUES(?,?)
			ON CONFLICT(key) DO UPDATE SET value=excluded.value`, imapFolderSettingsKey+id, string(raw)); err != nil {
			return IMAPFolderSettings{}, err
		}
		manual = update
	}
	assigned := map[string]string{}
	for _, entry := range resolveIMAPFolders(boxes, manual) {
		assigned[entry.local] = entry.remote
	}
	return IMAPFolderSettings{Available: available, Assigned: assigned, Manual: manual}, nil
}
