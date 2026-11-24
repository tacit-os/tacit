package backend

import (
	"slices"
	"testing"

	"github.com/emersion/go-imap/v2"
)

func TestResolveIMAPFoldersPrefersServerRoles(t *testing.T) {
	listed := []*imap.ListData{
		{Mailbox: "Archive"}, {Mailbox: "Old mail", Attrs: []imap.MailboxAttr{imap.MailboxAttrArchive}},
		{Mailbox: "Sent", Attrs: []imap.MailboxAttr{imap.MailboxAttrNoSelect}},
		{Mailbox: "Gesendet"}, {Mailbox: "Spam"}, {Mailbox: "Papierkorb"},
	}
	want := []imapFolder{{"Inbox", "INBOX"}, {"Archive", "Old mail"}, {"Spam", "Spam"},
		{"Sent", "Gesendet"}, {"Trash", "Papierkorb"}}
	if got := resolveIMAPFolders(listed); !slices.Equal(got, want) {
		t.Fatalf("mapped folders: %v, want %v", got, want)
	}
}

func TestResolveIMAPFoldersDoesNotGuessBetweenTwoArchives(t *testing.T) {
	listed := []*imap.ListData{
		{Mailbox: "Archive A", Attrs: []imap.MailboxAttr{imap.MailboxAttrArchive}},
		{Mailbox: "Archive B", Attrs: []imap.MailboxAttr{imap.MailboxAttrArchive}},
		{Mailbox: "Archiv"},
	}
	want := []imapFolder{{"Inbox", "INBOX"}}
	if got := resolveIMAPFolders(listed); !slices.Equal(got, want) {
		t.Fatalf("mapped ambiguous folder: %v", got)
	}
}

func TestManualFolderOverridesAndDisappearance(t *testing.T) {
	listed := []*imap.ListData{
		{Mailbox: "Archive", Attrs: []imap.MailboxAttr{imap.MailboxAttrArchive}},
		{Mailbox: "Manual archive"},
	}
	got := resolveIMAPFolders(listed, map[string]string{"Archive": "Manual archive"})
	if !slices.Equal(got, []imapFolder{{"Inbox", "INBOX"}, {"Archive", "Manual archive"}}) {
		t.Fatalf("override ignored: %v", got)
	}
	got = resolveIMAPFolders(listed[:1], map[string]string{"Archive": "Manual archive"})
	if !slices.Equal(got, []imapFolder{{"Inbox", "INBOX"}}) {
		t.Fatalf("disappeared mapping fell back to a different folder: %v", got)
	}
}
