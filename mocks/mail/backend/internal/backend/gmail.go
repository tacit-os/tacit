package backend

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"
)

const gmailRemotePrefix = "gmail:"
const gmailHistoryKey = "gmail-history:"
const gmailImportKey = "gmail-import:"

type gmailClient struct {
	http     *http.Client
	token    string
	auth     *gmailAuth
	cooldown *gmailCooldown
	onLimit  func()
}

// Workers in the same sync share the refreshed access token.
type gmailAuth struct {
	mu      sync.Mutex
	token   string
	refresh func(context.Context, string) (string, error)
}

func (a *gmailAuth) access() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.token
}

func (a *gmailAuth) renew(ctx context.Context, rejected string) (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.token != rejected {
		return a.token, nil
	}
	token, err := a.refresh(ctx, rejected)
	if err != nil {
		return "", err
	}
	a.token = token
	return token, nil
}

// A raw Gmail messages.get costs 60 units against 6,000 units per minute
// per user. Even the fastest interval leaves room for other Gmail calls.
const gmailReadInterval = 750 * time.Millisecond
const gmailFastestReadInterval = 650 * time.Millisecond

type gmailCooldown struct {
	mu              sync.Mutex
	until           time.Time
	nextRequest     time.Time
	interval        time.Duration
	successfulReads int
}

func (c *gmailCooldown) pause(delay time.Duration) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now()
	newPause := !c.until.After(now)
	if newPause {
		c.interval = min(2*c.readInterval(), 5*time.Second)
		c.successfulReads = 0
	}
	if until := now.Add(delay); until.After(c.until) {
		c.until = until
	}
	return newPause
}

func (c *gmailCooldown) readInterval() time.Duration {
	if c.interval == 0 {
		return gmailReadInterval
	}
	return c.interval
}

func (c *gmailCooldown) succeeded() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.until.After(time.Now()) {
		return
	}
	c.successfulReads++
	if c.successfulReads >= 30 {
		c.interval = max(c.readInterval()-50*time.Millisecond, gmailFastestReadInterval)
		c.successfulReads = 0
	}
}

func (c *gmailCooldown) limited() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.until.After(time.Now())
}

func (c *gmailCooldown) wait(ctx context.Context) error {
	for ctx.Err() == nil {
		c.mu.Lock()
		now := time.Now()
		due := c.nextRequest
		if c.until.After(due) {
			due = c.until
		}
		if !due.After(now) {
			c.nextRequest = now.Add(c.readInterval())
			c.mu.Unlock()
			return nil
		}
		c.mu.Unlock()
		if err := waitGmailRetry(ctx, due.Sub(now)); err != nil {
			return err
		}
	}
	return ctx.Err()
}

func waitGmailRetry(ctx context.Context, delay time.Duration) error {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func (p *InternetProvider) gmail() gmailClient {
	client := googleHTTPClient()
	client.Timeout = 90 * time.Second
	gmail := gmailClient{http: client, token: p.accessToken, cooldown: &gmailCooldown{}}
	if p.refreshGmailToken != nil {
		gmail.auth = &gmailAuth{token: p.accessToken, refresh: p.refreshGmailToken}
	}
	return gmail
}

type gmailMessage struct {
	ID           string
	HistoryID    string
	ThreadID     string
	LabelIDs     []string
	InternalDate string
	Raw          string
}

type gmailHTTPError int

func (e gmailHTTPError) Error() string { return fmt.Sprintf("Gmail API HTTP %d", e) }

type gmailRetryError struct {
	status gmailHTTPError
	wait   time.Duration
}

func (e gmailRetryError) Error() string { return e.status.Error() }
func (e gmailRetryError) Unwrap() error { return e.status }

func gmailRetryAfter(value string, now time.Time) time.Duration {
	if seconds, err := strconv.Atoi(value); err == nil && seconds > 0 {
		return time.Duration(min(seconds, 120)) * time.Second
	}
	if until, err := http.ParseTime(value); err == nil {
		return min(until.Sub(now), 2*time.Minute)
	}
	return 0
}

func (g gmailClient) request(ctx context.Context, method, path string, query url.Values, input, output any) error {
	if method != http.MethodGet {
		return g.requestOnce(ctx, method, path, query, input, output, g.accessToken())
	}
	renewed := false
	for attempt, limited := 0, 0; ; {
		if g.cooldown != nil {
			if err := g.cooldown.wait(ctx); err != nil {
				return err
			}
		}
		token := g.accessToken()
		err := g.requestOnce(ctx, method, path, query, input, output, token)
		if err == nil {
			if g.cooldown != nil {
				g.cooldown.succeeded()
			}
			return nil
		}
		if ctx.Err() != nil {
			return err
		}
		if !renewed && g.auth != nil && errors.Is(err, gmailHTTPError(http.StatusUnauthorized)) {
			if _, err := g.auth.renew(ctx, token); err != nil {
				return err
			}
			renewed = true
			continue
		}
		var retry gmailRetryError
		var network net.Error
		if errors.As(err, &retry) && (retry.status == http.StatusForbidden || retry.status == http.StatusTooManyRequests) {
			// Keep the inventory and committed messages while Gmail throttles reads.
			delay := max(retry.wait, min(time.Second<<min(limited, 6), time.Minute))
			limited++
			if g.cooldown != nil {
				if g.cooldown.pause(delay) && g.onLimit != nil {
					g.onLimit()
				}
			} else if err := waitGmailRetry(ctx, delay); err != nil {
				return err
			}
			continue
		}
		if attempt == 2 || (!errors.As(err, &retry) && !errors.As(err, &network) &&
			!errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF)) {
			return err
		}
		if err := waitGmailRetry(ctx, max(retry.wait, time.Second<<attempt)); err != nil {
			return err
		}
		attempt++
	}
}

// Only published error codes are safe to write to the log. Gmail's error
// messages, detail metadata, and request URLs may contain account data.
func gmailErrorReasons(body io.Reader) []string {
	var payload struct {
		Error struct {
			Errors  []struct{ Reason string }
			Details []struct{ Reason string }
		}
	}
	if json.NewDecoder(io.LimitReader(body, 64<<10)).Decode(&payload) != nil {
		return nil
	}
	var reasons []string
	for _, entries := range [][]struct{ Reason string }{payload.Error.Errors, payload.Error.Details} {
		for _, entry := range entries {
			switch entry.Reason {
			case "userRateLimitExceeded", "rateLimitExceeded", "dailyLimitExceeded", "quotaExceeded",
				"accessNotConfigured", "forbidden", "insufficientPermissions",
				"RATE_LIMIT_EXCEEDED", "QUOTA_EXCEEDED", "RESOURCE_EXHAUSTED",
				"SERVICE_DISABLED", "ACCESS_TOKEN_SCOPE_INSUFFICIENT":
				if !slices.Contains(reasons, entry.Reason) {
					reasons = append(reasons, entry.Reason)
				}
			}
		}
	}
	return reasons
}

func gmailLogRetryAfter(value string) string {
	if seconds, err := strconv.ParseUint(value, 10, 64); err == nil {
		return strconv.FormatUint(seconds, 10) + "s"
	}
	if until, err := http.ParseTime(value); err == nil {
		return until.UTC().Format(time.RFC3339)
	}
	return "unavailable"
}

func (g gmailClient) accessToken() string {
	if g.auth != nil {
		return g.auth.access()
	}
	return g.token
}

func (g gmailClient) requestOnce(ctx context.Context, method, path string, query url.Values, input, output any, token string) error {
	var body io.Reader
	if input != nil {
		data, err := json.Marshal(input)
		if err != nil {
			return err
		}
		body = bytes.NewReader(data)
	}
	endpoint := "https://gmail.googleapis.com/gmail/v1/users/me/" + path
	if len(query) > 0 {
		endpoint += "?" + query.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	if input != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := g.http.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		status := gmailHTTPError(res.StatusCode)
		retryable := res.StatusCode == http.StatusTooManyRequests || res.StatusCode >= 500
		if res.StatusCode == http.StatusForbidden || res.StatusCode == http.StatusTooManyRequests {
			reasons := gmailErrorReasons(res.Body)
			if res.StatusCode == http.StatusForbidden {
				retryable = slices.Contains(reasons, "rateLimitExceeded") || slices.Contains(reasons, "userRateLimitExceeded")
			}
			reason := strings.Join(reasons, ",")
			if reason == "" {
				reason = "unavailable"
			}
			log.Printf("Gmail API returned HTTP %d (reason=%s, retry-after=%s)",
				res.StatusCode, reason, gmailLogRetryAfter(res.Header.Get("Retry-After")))
		}
		_, _ = io.Copy(io.Discard, io.LimitReader(res.Body, 64<<10))
		if retryable {
			return gmailRetryError{status: status, wait: gmailRetryAfter(res.Header.Get("Retry-After"), time.Now())}
		}
		return status
	}
	if output == nil {
		_, err = io.Copy(io.Discard, res.Body)
		return err
	}
	return json.NewDecoder(res.Body).Decode(output)
}

func (g gmailClient) get(ctx context.Context, id, format string) (gmailMessage, error) {
	var message gmailMessage
	fields := "id,threadId,historyId,labelIds,internalDate"
	if format == "raw" {
		fields += ",raw"
	}
	query := url.Values{"format": {format}, "fields": {fields}}
	err := g.request(ctx, http.MethodGet, "messages/"+url.PathEscape(id), query, nil, &message)
	if err == nil && (message.ID != id || message.InternalDate == "") {
		err = errors.New("Gmail API returned an incomplete message")
	}
	return message, err
}

func (g gmailClient) list(ctx context.Context, search string) ([]string, error) {
	query := url.Values{"maxResults": {"500"}, "includeSpamTrash": {"true"},
		"q": {search + " -in:drafts"}, "fields": {"messages(id),nextPageToken"}}
	seen := map[string]bool{}
	var ids []string
	for {
		var page struct {
			Messages      []struct{ ID string }
			NextPageToken string
		}
		if err := g.request(ctx, http.MethodGet, "messages", query, nil, &page); err != nil {
			return nil, err
		}
		for _, message := range page.Messages {
			if message.ID != "" && !seen[message.ID] {
				seen[message.ID] = true
				ids = append(ids, message.ID)
			}
		}
		if page.NextPageToken == "" {
			return ids, nil
		}
		query.Set("pageToken", page.NextPageToken)
	}
}

func (g gmailClient) profile(ctx context.Context) (string, error) {
	var profile struct{ HistoryID string }
	err := g.request(ctx, http.MethodGet, "profile", url.Values{"fields": {"historyId"}}, nil, &profile)
	if err == nil && profile.HistoryID == "" {
		err = errors.New("Gmail API did not return a history cursor")
	}
	return profile.HistoryID, err
}

func (g gmailClient) changes(ctx context.Context, since string) ([]string, string, error) {
	query := url.Values{"startHistoryId": {since}, "maxResults": {"500"}}
	seen := map[string]bool{}
	var ids []string
	for {
		var page struct {
			History []struct {
				Messages                                                   []struct{ ID string }
				MessagesAdded, MessagesDeleted, LabelsAdded, LabelsRemoved []struct {
					Message struct{ ID string }
				}
			}
			HistoryID, NextPageToken string
		}
		if err := g.request(ctx, http.MethodGet, "history", query, nil, &page); err != nil {
			return nil, "", err
		}
		add := func(id string) {
			if id != "" && !seen[id] {
				seen[id] = true
				ids = append(ids, id)
			}
		}
		for _, event := range page.History {
			for _, message := range event.Messages {
				add(message.ID)
			}
			for _, changes := range [][]struct{ Message struct{ ID string } }{
				event.MessagesAdded, event.MessagesDeleted, event.LabelsAdded, event.LabelsRemoved,
			} {
				for _, change := range changes {
					add(change.Message.ID)
				}
			}
		}
		if page.NextPageToken == "" {
			if page.HistoryID == "" {
				return nil, "", errors.New("Gmail API did not return a history cursor")
			}
			return ids, page.HistoryID, nil
		}
		query.Set("pageToken", page.NextPageToken)
	}
}

func (record gmailMessage) apply(m *Message) error {
	if record.InternalDate != "" {
		ms, err := strconv.ParseInt(record.InternalDate, 10, 64)
		if err != nil {
			return err
		}
		m.Date = time.UnixMilli(ms)
	}
	m.GmailLabels = record.LabelIDs
	if record.HistoryID != "" {
		m.GmailHistoryID = record.HistoryID
	}
	m.Unread = slices.Contains(record.LabelIDs, "UNREAD")
	m.Flagged = slices.Contains(record.LabelIDs, "STARRED")
	m.Important = slices.Contains(record.LabelIDs, "IMPORTANT")
	prior := m.Mailbox
	switch {
	case slices.Contains(record.LabelIDs, "TRASH"):
		m.Mailbox = "Trash"
		if prior != "" && prior != "Trash" {
			m.TrashOrigin = prior
		}
	case slices.Contains(record.LabelIDs, "SPAM"):
		m.Mailbox = "Spam"
	case slices.Contains(record.LabelIDs, "INBOX"):
		m.Mailbox = "Inbox"
	case slices.Contains(record.LabelIDs, "SENT"):
		m.Mailbox = "Sent"
	default:
		m.Mailbox = "Archive"
	}
	if m.Mailbox != "Trash" {
		m.TrashOrigin = ""
	}
	return nil
}

func (record gmailMessage) parse() (Message, error) {
	raw, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(record.Raw, "="))
	if err != nil || len(raw) == 0 {
		return Message{}, errors.New("Gmail API did not return a valid message body")
	}
	m, err := ReadMIME(bytes.NewReader(raw))
	if err != nil {
		m.BodyText = "Tacit could not read this message. Open it with your mail provider to view the original."
	}
	m.RemoteID = gmailRemotePrefix + record.ID
	if record.ThreadID != "" {
		m.ConversationID = gmailRemotePrefix + record.ThreadID
	}
	return m, record.apply(&m)
}
