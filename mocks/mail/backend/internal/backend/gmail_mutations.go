package backend

import (
	"context"
	"net/http"
	"net/url"
	"strings"
)

type gmailLabelPatch struct {
	Add    []string `json:"addLabelIds,omitempty"`
	Remove []string `json:"removeLabelIds,omitempty"`
}

func (g gmailClient) patchMessage(ctx context.Context, message *Message, patch gmailLabelPatch) error {
	if len(patch.Add) == 0 && len(patch.Remove) == 0 {
		return nil
	}
	var record gmailMessage
	path := "messages/" + url.PathEscape(strings.TrimPrefix(message.RemoteID, gmailRemotePrefix)) + "/modify"
	if err := g.request(ctx, http.MethodPost, path, nil, patch, &record); err != nil {
		return err
	}
	return record.apply(message)
}

func (g gmailClient) patchFlags(ctx context.Context, message *Message, flags MessagePatch) error {
	var patch gmailLabelPatch
	for _, flag := range []struct {
		label string
		value *bool
	}{{"UNREAD", flags.Unread}, {"STARRED", flags.Flagged}} {
		if flag.value == nil {
			continue
		}
		if *flag.value {
			patch.Add = append(patch.Add, flag.label)
		} else {
			patch.Remove = append(patch.Remove, flag.label)
		}
	}
	return g.patchMessage(ctx, message, patch)
}

func (g gmailClient) move(ctx context.Context, message *Message, destination string) error {
	switch destination {
	case "Inbox", "Archive", "Sent", "Spam", "Trash":
	default:
		return ErrConflict
	}
	path := "messages/" + url.PathEscape(strings.TrimPrefix(message.RemoteID, gmailRemotePrefix))
	if destination == "Trash" || message.Mailbox == "Trash" {
		action := "/trash"
		if destination != "Trash" {
			action = "/untrash"
		}
		var record gmailMessage
		if err := g.request(ctx, http.MethodPost, path+action, nil, nil, &record); err != nil {
			return err
		}
		// The caller records the prior folder when committing a move to Trash.
		message.GmailLabels, message.GmailHistoryID = record.LabelIDs, record.HistoryID
		if destination == "Trash" {
			return nil
		}
	}
	var patch gmailLabelPatch
	switch destination {
	case "Inbox":
		patch = gmailLabelPatch{Add: []string{"INBOX"}, Remove: []string{"SPAM"}}
	case "Archive", "Sent":
		// Gmail assigns SENT itself. Moving a sent message out of the inbox retains it.
		patch = gmailLabelPatch{Remove: []string{"INBOX", "SPAM"}}
	case "Spam":
		patch = gmailLabelPatch{Add: []string{"SPAM"}, Remove: []string{"INBOX"}}
	}
	prior := message.Mailbox
	if err := g.patchMessage(ctx, message, patch); err != nil {
		return err
	}
	message.Mailbox = prior
	return nil
}

func remoteMail(remoteID string) bool {
	return strings.HasPrefix(remoteID, "imap:") || strings.HasPrefix(remoteID, gmailRemotePrefix)
}
