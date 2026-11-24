package backend

import (
	"context"
	"database/sql"
	"fmt"
	"slices"
	"strconv"
	"strings"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

type imapLocation struct {
	mailbox  string
	validity uint32
	uid      imap.UID
}

func (s *Store) internetForMutation(ctx context.Context, tx *sql.Tx, accountID string) (*InternetProvider, error) {
	var account Account
	err := tx.QueryRowContext(ctx, "SELECT id,email,provider FROM accounts WHERE id=?", accountID).
		Scan(&account.ID, &account.Email, &account.Provider)
	if err != nil {
		return nil, mapped(err)
	}
	if account.Provider == OfflineIMAP || account.Provider == stoppingIMAP || account.Provider == removingIMAP {
		return nil, ErrConflict
	}
	var result *InternetProvider
	switch transport := s.remoteTransports[account.Provider].(type) {
	case *ManagedAccounts:
		result, err = transport.transport(ctx, account)
		if err != nil {
			return nil, err
		}
	case *InternetProvider:
		if transport.Email == account.Email {
			result = transport
		}
	}
	if result != nil {
		copy := *result
		copy.folderOverrides, err = loadIMAPFolderSettings(ctx, tx, accountID)
		return &copy, err
	}
	if account.Provider == ManagedIMAP || account.Provider == "imap-smtp" {
		return nil, ErrCredentialStore
	}
	return nil, nil
}

func (s *Store) moveRemote(ctx context.Context, tx *sql.Tx, messages []Message, destination string) error {
	for _, message := range messages {
		if !remoteMail(message.RemoteID) {
			continue
		}
		transport, err := s.internetForMutation(ctx, tx, message.AccountID)
		if err != nil {
			return err
		}
		if transport != nil {
			return transport.moveTrash(ctx, messages, destination)
		}
		break
	}
	return nil
}

func (s *Store) restoreRemote(ctx context.Context, tx *sql.Tx, messages []Message, destination func(Message) string) error {
	for _, target := range []string{"Inbox", "Archive", "Sent", "Spam"} {
		var batch []Message
		var indexes []int
		for i, message := range messages {
			if destination(message) == target {
				batch = append(batch, message)
				indexes = append(indexes, i)
			}
		}
		if err := s.moveRemote(ctx, tx, batch, target); err != nil {
			return err
		}
		for i, index := range indexes {
			messages[index] = batch[i]
		}
	}
	return nil
}

func (p *InternetProvider) patchFlags(ctx context.Context, remoteID string, patch MessagePatch) error {
	loc, err := parseIMAPLocation(remoteID)
	if err != nil {
		return err
	}
	conn, closeConn, err := p.dialMail(ctx, p.IMAP)
	if err != nil {
		return err
	}
	defer closeConn()
	client := imapclient.New(conn, nil)
	if err := p.authenticateIMAP(client); err != nil {
		return err
	}
	return applyIMAPFlags(client, loc, patch)
}

func applyIMAPFlags(client *imapclient.Client, loc imapLocation, patch MessagePatch) error {
	selected, err := client.Select(loc.mailbox, nil).Wait()
	if err != nil {
		return err
	}
	if selected.UIDValidity != loc.validity {
		return ErrConflict
	}
	set := imap.UIDSetNum(loc.uid)
	found, err := client.UIDSearch(&imap.SearchCriteria{UID: []imap.UIDSet{set}}, nil).Wait()
	if err != nil {
		return err
	}
	if !slices.Contains(found.AllUIDs(), loc.uid) {
		return ErrNotFound
	}
	var add, remove []imap.Flag
	for _, flag := range []struct {
		imapFlag imap.Flag
		active   *bool
		invert   bool
	}{{imap.FlagSeen, patch.Unread, true}, {imap.FlagFlagged, patch.Flagged, false}} {
		if flag.active == nil {
			continue
		}
		if *flag.active != flag.invert {
			add = append(add, flag.imapFlag)
		} else {
			remove = append(remove, flag.imapFlag)
		}
	}
	for _, flags := range []imap.StoreFlags{
		{Op: imap.StoreFlagsAdd, Silent: true, Flags: add},
		{Op: imap.StoreFlagsDel, Silent: true, Flags: remove},
	} {
		if len(flags.Flags) > 0 {
			if err := client.Store(set, &flags, nil).Close(); err != nil {
				return err
			}
		}
	}
	return nil
}

func parseIMAPLocation(remoteID string) (imapLocation, error) {
	path, ok := strings.CutPrefix(remoteID, "imap:")
	if !ok {
		return imapLocation{}, ErrInvalid
	}
	i := strings.LastIndexByte(path, ':')
	if i < 0 {
		return imapLocation{}, ErrInvalid
	}
	path, uid := path[:i], path[i+1:]
	i = strings.LastIndexByte(path, ':')
	if i <= 0 {
		return imapLocation{}, ErrInvalid
	}
	validity, err := strconv.ParseUint(path[i+1:], 10, 32)
	number, uidErr := strconv.ParseUint(uid, 10, 32)
	if err != nil || uidErr != nil || validity == 0 || number == 0 {
		return imapLocation{}, ErrInvalid
	}
	return imapLocation{path[:i], uint32(validity), imap.UID(number)}, nil
}

func (p *InternetProvider) moveTrash(ctx context.Context, messages []Message, destination string) error {
	type group struct {
		source  imapLocation
		indexes []int
		uids    []imap.UID
	}
	var groups []group
	for i, message := range messages {
		if strings.HasPrefix(message.RemoteID, gmailRemotePrefix) {
			if p.accessToken == "" {
				return ErrCredentialStore
			}
			if err := p.gmail().move(ctx, &messages[i], destination); err != nil {
				return err
			}
			continue
		}
		if !strings.HasPrefix(message.RemoteID, "imap:") {
			continue
		}
		location, err := parseIMAPLocation(message.RemoteID)
		if err != nil {
			return err
		}
		if destination == "Inbox" && strings.EqualFold(location.mailbox, "INBOX") {
			// Older local-only trash operations left the message in INBOX.
			continue
		}
		index := slices.IndexFunc(groups, func(g group) bool {
			return g.source.mailbox == location.mailbox && g.source.validity == location.validity
		})
		if index < 0 {
			groups = append(groups, group{source: location})
			index = len(groups) - 1
		}
		groups[index].indexes = append(groups[index].indexes, i)
		groups[index].uids = append(groups[index].uids, location.uid)
	}
	if len(groups) == 0 {
		return nil
	}
	conn, closeConn, err := p.dialMail(ctx, p.IMAP)
	if err != nil {
		return err
	}
	defer closeConn()
	client := imapclient.New(conn, nil)
	if err := p.authenticateIMAP(client); err != nil {
		return err
	}
	for _, group := range groups {
		if err := moveIMAPTrash(client, messages, group.indexes, group.source, group.uids, destination, p.folderOverrides); err != nil {
			return err
		}
	}
	return nil
}

func moveIMAPTrash(client *imapclient.Client, messages []Message, indexes []int, source imapLocation, uids []imap.UID, destination string, overrides map[string]string) error {
	caps := client.Caps()
	// Avoid the client's COPY/STORE/EXPUNGE fallback, which can expunge unrelated mail.
	if !caps.Has(imap.CapMove) || !caps.Has(imap.CapUIDPlus) {
		return fmt.Errorf("IMAP server lacks MOVE or UIDPLUS")
	}
	target, err := remoteIMAPFolder(client, destination, overrides)
	if err != nil {
		return err
	}
	if target == source.mailbox {
		return nil
	}
	selected, err := client.Select(source.mailbox, nil).Wait()
	if err != nil {
		return err
	}
	if selected.UIDValidity != source.validity {
		return ErrConflict
	}
	set := imap.UIDSetNum(uids...)
	found, err := client.UIDSearch(&imap.SearchCriteria{UID: []imap.UIDSet{set}}, nil).Wait()
	if err != nil {
		return err
	}
	if len(found.AllUIDs()) != len(uids) {
		return ErrNotFound
	}
	moved, err := client.Move(set, target).Wait()
	if err != nil {
		return err
	}
	from, fromOK := moved.SourceUIDs.(imap.UIDSet)
	to, toOK := moved.DestUIDs.(imap.UIDSet)
	if !fromOK || !toOK || moved.UIDValidity == 0 {
		return fmt.Errorf("IMAP MOVE omitted destination UIDs")
	}
	oldUIDs, _ := from.Nums()
	newUIDs, _ := to.Nums()
	if len(oldUIDs) != len(uids) || len(newUIDs) != len(uids) {
		return fmt.Errorf("IMAP MOVE returned incomplete destination UIDs")
	}
	for i, uid := range uids {
		index := slices.Index(oldUIDs, uid)
		if index < 0 {
			return fmt.Errorf("IMAP MOVE did not return UID %d", uid)
		}
		messages[indexes[i]].RemoteID = fmt.Sprintf("imap:%s:%d:%d", target, moved.UIDValidity, newUIDs[index])
	}
	return nil
}
