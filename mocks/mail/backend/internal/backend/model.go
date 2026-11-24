package backend

import (
	"errors"
	"time"

	"tacit.local/quotedbody"
)

var ErrInvalid = errors.New("invalid input")
var ErrNotFound = errors.New("not found")
var ErrConflict = errors.New("conflict")

type Address struct {
	Name  string `json:"name,omitempty"`
	Email string `json:"email"`
}
type Attachment struct {
	Inline    bool   `json:"inline,omitempty"`
	ID        string `json:"id"`
	Filename  string `json:"filename"`
	MediaType string `json:"media_type"`
	Size      int    `json:"size"`
	Width     int    `json:"width,omitempty"`
	Height    int    `json:"height,omitempty"`
	// Data is only an in-process fixture/import convenience. JSON uses immutable IDs.
	Data []byte `json:"-"`
}

// BodyParts is persisted derived data; the original bodies remain authoritative.
// Source identifies their bytes, so flag-only writes can reuse the split.
type BodyParts struct {
	Version int               `json:"version"`
	Source  string            `json:"source"`
	Text    []quotedbody.Part `json:"text,omitempty"`
	HTML    []quotedbody.Part `json:"html,omitempty"`
}
type Message struct {
	BodyParts           *BodyParts    `json:"body_parts,omitempty"`
	RemoteImagesAllowed bool          `json:"remote_images_allowed,omitempty"`
	RemoteImages        []RemoteImage `json:"remote_images,omitempty"`
	Important           bool          `json:"important,omitempty"`
	Importance          string        `json:"importance,omitempty"`
	GmailLabels         []string      `json:"gmail_labels,omitempty"`
	GmailHistoryID      string        `json:"gmail_history_id,omitempty"`
	Automated           bool          `json:"automated,omitempty"`
	TrashOrigin         string        `json:"trash_origin,omitempty"`
	ID                  string        `json:"id"`
	AccountID           string        `json:"account_id"`
	RemoteID            string        `json:"remote_id,omitempty"`
	ConversationID      string        `json:"conversation_id"`
	MessageID           string        `json:"message_id,omitempty"`
	ReplySourceID       string        `json:"reply_source_id,omitempty"`
	InReplyTo           string        `json:"in_reply_to,omitempty"`
	References          []string      `json:"references,omitempty"`
	From                Address       `json:"from"`
	To                  []Address     `json:"to"`
	Cc                  []Address     `json:"cc,omitempty"`
	Bcc                 []Address     `json:"bcc,omitempty"`
	Subject             string        `json:"subject"`
	BodyText            string        `json:"body_text"`
	BodyHTML            string        `json:"body_html,omitempty"`
	HasHTML             bool          `json:"has_html,omitempty"`
	Mailbox             string        `json:"mailbox"`
	Unread              bool          `json:"unread"`
	Flagged             bool          `json:"flagged"`
	Date                time.Time     `json:"date"`
	Attachments         []Attachment  `json:"attachments"`
}
type Account struct {
	CategoryProvider  string      `json:"category_provider,omitempty"`
	SyncSnapshot      *SyncResult `json:"sync_snapshot,omitempty"`
	RecentImportReady bool        `json:"recent_import_ready,omitempty"`
	ImportPending     bool        `json:"import_pending,omitempty"`
	ID                string      `json:"id"`
	Name              string      `json:"name"`
	Email             string      `json:"email"`
	Provider          string      `json:"provider"`
}
type MessagePatch struct {
	Unread  *bool  `json:"unread,omitempty"`
	Flagged *bool  `json:"flagged,omitempty"`
	Mailbox string `json:"mailbox,omitempty"`
}
type Query struct {
	AccountID, Mailbox, Search string
	Limit, Offset              int
}
type Page struct {
	Messages []Message `json:"messages"`
	Total    int       `json:"total"`
	Limit    int       `json:"limit"`
	Offset   int       `json:"offset"`
}
type Batch struct {
	Messages []Message
	Cursor   string
	HasMore  bool
}
type SyncResult struct {
	LastSynced        int64             `json:"last_synced,omitempty"`
	SyncedFolders     map[string]string `json:"synced_folders,omitempty"`
	SentCopyPending   bool              `json:"sent_copy_pending,omitempty"`
	NewUnread         int               `json:"new_unread,omitempty"`
	NewLikelyPersonal int               `json:"new_likely_personal,omitempty"`
	Received          int               `json:"received"`
	Cursor            string            `json:"cursor"`
	HasMore           bool              `json:"has_more"`
}
type Job struct {
	UndoUntil int64   `json:"undo_until,omitempty"`
	ID        string  `json:"id"`
	MessageID string  `json:"message_id"`
	Key       string  `json:"idempotency_key"`
	State     string  `json:"state"`
	Attempts  int     `json:"attempts"`
	LastError string  `json:"last_error,omitempty"`
	Message   Message `json:"-"`
}
type Receipt struct {
	RemoteID string
	SentAt   time.Time
}
