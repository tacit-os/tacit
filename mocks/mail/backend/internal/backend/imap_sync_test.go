package backend

import (
	"strings"
	"testing"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

func TestIMAPSentCopyReusesLocalSMTPMessage(t *testing.T) {
	store, _, _ := openTest(t)
	local := incoming("smtp:submission")
	local.Mailbox = "Sent"
	local.MessageID = "<sent-test@example.org>"
	if _, err := store.CacheBatch(ctx, "work", Batch{Messages: []Message{local}}); err != nil {
		t.Fatal(err)
	}
	var id string
	if err := store.db.QueryRow("SELECT id FROM messages WHERE remote_id=?", local.RemoteID).Scan(&id); err != nil {
		t.Fatal(err)
	}
	remote := local
	remote.AccountID = "work"
	remote.RemoteID = "imap:Gesendet:40:7"
	result, err := store.applyIMAPFolders(ctx, "work", []imapFolder{{"Sent", "Gesendet"}},
		map[string]string{}, map[string]bool{remote.RemoteID: true}, []Message{remote}, nil)
	if err != nil || result.NewUnread != 0 {
		t.Fatalf("Sent reconciliation: %+v, %v", result, err)
	}
	got, err := store.Get(ctx, id)
	if err != nil || got.RemoteID != remote.RemoteID || got.Mailbox != "Sent" {
		t.Fatalf("existing Sent copy: %+v, %v", got, err)
	}
}

func TestIMAPNotificationsExcludeAutomatedMessagesFromPeopleCount(t *testing.T) {
	store, _, _ := openTest(t)
	manual := incoming("imap:INBOX:1:4")
	manual.AccountID = "work"
	bulk := incoming("imap:INBOX:1:5")
	bulk.AccountID = "work"
	bulk.Automated = true
	result, err := store.applyIMAPFolders(ctx, "work", []imapFolder{{"Inbox", "INBOX"}},
		map[string]string{}, map[string]bool{manual.RemoteID: true, bulk.RemoteID: true}, []Message{manual, bulk}, nil)
	if err != nil || result.NewUnread != 2 || result.NewLikelyPersonal != 1 {
		t.Fatalf("notification counts: %+v, %v", result, err)
	}
}

func TestIMAPRestoreKeepsOneLocalMessageAndItsThread(t *testing.T) {
	store, _, _ := openTest(t)
	old := incoming("imap:Papierkorb:30:4")
	old.MessageID = "restore@example.org"
	old.Mailbox = "Trash"
	if _, err := store.CacheBatch(ctx, "work", Batch{Messages: []Message{old}}); err != nil {
		t.Fatal(err)
	}
	known, err := cachedIMAPLocations(ctx, store.db, "work")
	if err != nil {
		t.Fatal(err)
	}
	localID := known[old.RemoteID]
	restored := old
	restored.RemoteID = "imap:INBOX:10:52"
	restored.AccountID = "work"
	restored.Mailbox = "Inbox"
	result, err := store.applyIMAPFolders(ctx, "work", []imapFolder{{"Inbox", "INBOX"}, {"Trash", "Papierkorb"}}, known,
		map[string]bool{restored.RemoteID: true}, []Message{restored}, nil)
	if err != nil || result.Received != 1 {
		t.Fatalf("restore: %+v, %v", result, err)
	}
	got, err := store.Get(ctx, localID)
	if err != nil || got.Mailbox != "Inbox" || got.RemoteID != restored.RemoteID ||
		got.ConversationID != old.ConversationID {
		t.Fatalf("restored message lost its local identity: %+v, %v", got, err)
	}
	known, err = cachedIMAPLocations(ctx, store.db, "work")
	if err != nil || len(known) != 1 || known[restored.RemoteID] != localID {
		t.Fatalf("duplicate or missing IMAP entry: %v, %v", known, err)
	}
}

func TestMalformedIMAPBodyPreservesEnvelope(t *testing.T) {
	section := &imap.FetchItemBodySection{}
	item := &imapclient.FetchMessageBuffer{
		Envelope: &imap.Envelope{Subject: "Original subject", From: []imap.Address{
			{Mailbox: "sender", Host: "example.org"},
		}},
		BodySection: []imapclient.FetchBodySectionBuffer{
			{Section: section, Bytes: []byte("malformed header without colon")},
		},
	}
	got := receivedIMAPMessage(item, section)
	if got.Subject != "Original subject" || got.From.Email != "sender@example.org" ||
		!strings.Contains(got.BodyText, "Open it with your mail provider") {
		t.Fatalf("could not recover message metadata: %+v", got)
	}
}

func TestImportCountIncludesOnlyCachedMessagesStillOnServer(t *testing.T) {
	known := map[string]string{
		"cached":  "local-id",
		"deleted": "old-id",
		"ignored": "",
	}
	seen := map[string]bool{"cached": true, "ignored": true, "pending": true}
	if got := countCachedIMAPMessages(known, seen); got != 1 {
		t.Fatalf("cached progress = %d, want 1", got)
	}
}
