package backend

import (
	"bufio"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

func TestIMAPTrashMovesOnlySelectedUIDsAndRecordsDestination(t *testing.T) {
	clientConn, serverConn := net.Pipe()
	defer clientConn.Close()
	defer serverConn.Close()
	serverConn.SetDeadline(time.Now().Add(3 * time.Second))
	go func() {
		defer serverConn.Close()
		fmt.Fprint(serverConn, "* PREAUTH [CAPABILITY IMAP4rev1 MOVE UIDPLUS SPECIAL-USE] test server\r\n")
		reader := bufio.NewReader(serverConn)
		for _, step := range []struct {
			command, response string
		}{
			{`LIST "" "*" RETURN (SPECIAL-USE)`, "* LIST (\\Trash) \"/\" \"Papierkorb\"\r\n"},
			{"SELECT INBOX", "* 3 EXISTS\r\n* OK [UIDVALIDITY 42] current\r\n"},
			{"UID SEARCH UID 7,11", "* SEARCH 7 11\r\n"},
			{`UID MOVE 7,11 Papierkorb`, "* OK [COPYUID 99 7,11 21,22] moved\r\n"},
		} {
			line, err := reader.ReadString('\n')
			if err != nil {
				t.Errorf("read %s: %v", step.command, err)
				return
			}
			tag, command, _ := strings.Cut(strings.TrimSpace(line), " ")
			if strings.ReplaceAll(command, "\"Papierkorb\"", "Papierkorb") != step.command {
				t.Errorf("got %q, want %q", command, step.command)
				return
			}
			fmt.Fprintf(serverConn, "%s%s OK done\r\n", step.response, tag)
		}
	}()
	client := imapclient.New(clientConn, nil)
	messages := []Message{{RemoteID: "imap:INBOX:42:11"}, {RemoteID: "imap:INBOX:42:7"}}
	err := moveIMAPTrash(client, messages, []int{1, 0}, imapLocation{"INBOX", 42, 7}, []imap.UID{7, 11}, "Trash", nil)
	if err != nil {
		t.Fatal(err)
	}
	if messages[0].RemoteID != "imap:Papierkorb:99:22" || messages[1].RemoteID != "imap:Papierkorb:99:21" {
		t.Fatalf("wrong destination identities: %q, %q", messages[0].RemoteID, messages[1].RemoteID)
	}
}

func TestIMAPFlagsUseOnlyTheSelectedUID(t *testing.T) {
	clientConn, serverConn := net.Pipe()
	defer clientConn.Close()
	defer serverConn.Close()
	_ = serverConn.SetDeadline(time.Now().Add(3 * time.Second))
	go func() {
		defer serverConn.Close()
		fmt.Fprint(serverConn, "* PREAUTH [CAPABILITY IMAP4rev1] test server\r\n")
		reader := bufio.NewReader(serverConn)
		for _, step := range []struct{ command, response string }{
			{"SELECT INBOX", "* 10 EXISTS\r\n* OK [UIDVALIDITY 42] current\r\n"},
			{"UID SEARCH UID 7", "* SEARCH 7\r\n"},
			{"UID STORE 7 +FLAGS.SILENT (\\Flagged)", ""},
			{"UID STORE 7 -FLAGS.SILENT (\\Seen)", ""},
		} {
			line, err := reader.ReadString('\n')
			if err != nil {
				t.Errorf("read %s: %v", step.command, err)
				return
			}
			tag, command, _ := strings.Cut(strings.TrimSpace(line), " ")
			if command != step.command {
				t.Errorf("got %q, want %q", command, step.command)
				return
			}
			fmt.Fprintf(serverConn, "%s%s OK done\r\n", step.response, tag)
		}
	}()
	unread, flagged := true, true
	client := imapclient.New(clientConn, nil)
	if err := applyIMAPFlags(client, imapLocation{"INBOX", 42, 7},
		MessagePatch{Unread: &unread, Flagged: &flagged}); err != nil {
		t.Fatal(err)
	}
}
