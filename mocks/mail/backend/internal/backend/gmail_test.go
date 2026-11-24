package backend

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

type gmailTestTransport func(*http.Request) (*http.Response, error)

func (f gmailTestTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func gmailTestResponse(status int, data string) *http.Response {
	return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(data))}
}

func TestGmailReadRenewsRejectedToken(t *testing.T) {
	for _, status := range []int{http.StatusOK, http.StatusUnauthorized} {
		t.Run(strconv.Itoa(status), func(t *testing.T) {
			var tokens []string
			refreshes := 0
			client := gmailClient{
				http: &http.Client{Transport: gmailTestTransport(func(r *http.Request) (*http.Response, error) {
					token := r.Header.Get("Authorization")
					tokens = append(tokens, token)
					if token == "Bearer expired" {
						return gmailTestResponse(http.StatusUnauthorized, "{}"), nil
					}
					return gmailTestResponse(status, "{}"), nil
				})},
				auth: &gmailAuth{token: "expired", refresh: func(_ context.Context, rejected string) (string, error) {
					refreshes++
					if rejected != "expired" {
						t.Fatalf("unexpected rejected token: %s", rejected)
					}
					return "renewed", nil
				}},
			}
			err := client.request(context.Background(), http.MethodGet, "messages/one", nil, nil, nil)
			if status == http.StatusOK {
				if err != nil {
					t.Fatal(err)
				}
				if err := client.request(context.Background(), http.MethodGet, "messages/two", nil, nil, nil); err != nil {
					t.Fatal(err)
				}
			} else if err != gmailHTTPError(http.StatusUnauthorized) {
				t.Fatalf("expected a persistent 401, got %v", err)
			}
			want := "Bearer expired,Bearer renewed"
			if status == http.StatusOK {
				want += ",Bearer renewed"
			}
			if refreshes != 1 || strings.Join(tokens, ",") != want {
				t.Fatalf("requests %v, refreshes %d", tokens, refreshes)
			}
		})
	}
}

func TestGmailCleanImportAndHistory(t *testing.T) {
	store, _, _ := openTest(t)
	legacy := incoming("imap:INBOX:4:1")
	legacy.Mailbox = "Inbox"
	if _, err := store.CacheBatch(ctx, "work", Batch{Messages: []Message{legacy}}); err != nil {
		t.Fatal(err)
	}
	draft, err := store.SaveDraft(ctx, Message{AccountID: "work", Subject: "Local draft"})
	if err != nil {
		t.Fatal(err)
	}

	var mu sync.Mutex
	var downloaded []string
	var recentReady bool
	step := 0
	gmail := gmailClient{http: &http.Client{Transport: gmailTestTransport(func(r *http.Request) (*http.Response, error) {
		mu.Lock()
		defer mu.Unlock()
		path := strings.TrimPrefix(r.URL.Path, "/gmail/v1/users/me/")
		if step == 0 {
			return gmailTestResponse(403, "{}"), nil
		}
		switch path {
		case "profile":
			return gmailTestResponse(200, `{"historyId":"100"}`), nil
		case "messages":
			if r.URL.Query().Get("includeSpamTrash") != "true" {
				t.Error("inventory omitted Spam and Trash")
			}
			query := r.URL.Query().Get("q")
			if timestamp, ok := strings.CutPrefix(query, "after:"); ok {
				epoch, err := strconv.ParseInt(strings.Fields(timestamp)[0], 10, 64)
				expected := time.Now().AddDate(-1, 0, 0).Unix() - 1
				if err != nil || epoch < expected-60 || epoch > expected+60 {
					t.Errorf("foreground query did not use the one-year cutoff")
				}
				if r.URL.Query().Get("pageToken") == "" {
					return gmailTestResponse(200, `{"messages":[{"id":"recent"}],"nextPageToken":"two"}`), nil
				}
				return gmailTestResponse(200, `{"messages":[{"id":"recent"}]}`), nil
			}
			if !recentReady {
				t.Error("older inventory started before recent mail was released")
			}
			return gmailTestResponse(200, `{"messages":[{"id":"old"}]}`), nil
		case "history":
			if step == 1 {
				return gmailTestResponse(200, `{"historyId":"101"}`), nil
			}
			return gmailTestResponse(200, `{"historyId":"103","history":[{"labelsRemoved":[{"message":{"id":"recent"}}],"messagesDeleted":[{"message":{"id":"old"}}]}]}`), nil
		case "messages/recent", "messages/old":
			gmailID := strings.TrimPrefix(path, "messages/")
			if step == 2 && gmailID == "old" {
				return gmailTestResponse(404, "{}"), nil
			}
			record := gmailMessage{ID: gmailID, HistoryID: "101", InternalDate: strconv.FormatInt(time.Now().AddDate(0, -6, 0).UnixMilli(), 10),
				LabelIDs: []string{"INBOX", "SENT", "UNREAD"}}
			if gmailID == "old" {
				record.InternalDate = "1200000000000"
				record.LabelIDs = nil
			}
			if step == 2 {
				record.HistoryID = "103"
				record.LabelIDs = []string{"SENT"}
			}
			if r.URL.Query().Get("format") == "raw" {
				downloaded = append(downloaded, gmailID)
				record.Raw = base64.RawURLEncoding.EncodeToString([]byte("From: Sender <sender@example.org>\r\nSubject: Example " +
					gmailID + "\r\nMessage-ID: <" + gmailID + "@example.org>\r\n\r\nSearchable body\r\n"))
			}
			payload, _ := json.Marshal(record)
			return gmailTestResponse(200, string(payload)), nil
		default:
			t.Errorf("unexpected path %s", path)
			return gmailTestResponse(500, "{}"), nil
		}
	})}}
	account, err := store.Account(ctx, "work")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.syncGmail(ctx, account, gmail, nil); err == nil {
		t.Fatal("expected unavailable Gmail API to stop migration")
	}
	inbox, err := store.List(ctx, Query{AccountID: "work", Mailbox: "Inbox"})
	if err != nil || !containsTestRemote(inbox, legacy.RemoteID) {
		t.Fatalf("old cache disappeared before the API was reachable: %v", err)
	}

	step = 1
	var events [][2]int
	_, err = store.syncGmail(ctx, account, gmail, func(saved, total int) {
		events = append(events, [2]int{saved, total})
		if saved == -2 {
			mu.Lock()
			recentReady = true
			mu.Unlock()
			results, err := store.List(ctx, Query{AccountID: "work", Search: "Searchable"})
			if err != nil || results.Total != 1 || results.Messages[0].RemoteID != "gmail:recent" {
				t.Errorf("recent phase was not in the search index: %v, %v", results.Total, err)
			}
		}
	})
	if err != nil {
		t.Fatalf("clean import: %v, updates=%v", err, events)
	}
	if strings.Join(downloaded, ",") != "recent,old" {
		t.Fatalf("downloaded in order: %v", downloaded)
	}
	if _, err := store.Get(ctx, draft.ID); err != nil {
		t.Fatalf("local draft was lost: %v", err)
	}
	inbox, err = store.List(ctx, Query{AccountID: "work", Mailbox: "Inbox", Search: "Searchable"})
	if err != nil || inbox.Total != 1 {
		t.Fatalf("inbox: %d, %v", inbox.Total, err)
	}
	sent, err := store.List(ctx, Query{AccountID: "work", Mailbox: "Sent", Search: "Searchable"})
	if err != nil || sent.Total != 1 || sent.Messages[0].ID != inbox.Messages[0].ID {
		t.Fatalf("sent must use same cached message: %d, %v", sent.Total, err)
	}
	account, _ = store.Account(ctx, "work")
	if account.ImportPending || !account.RecentImportReady {
		t.Fatalf("import markers left pending: %+v", account)
	}

	step = 2
	_, err = store.syncGmail(ctx, account, gmail, nil)
	if err != nil {
		t.Fatal(err)
	}
	result, err := store.List(ctx, Query{AccountID: "work", Search: "Searchable"})
	if err != nil || result.Total != 1 || result.Messages[0].Mailbox != "Sent" ||
		result.Messages[0].Unread || result.Messages[0].ID != sent.Messages[0].ID || len(downloaded) != 2 {
		t.Fatalf("history did not update/delete cached mail without fetching bodies again: %+v, %v", result, err)
	}
}

func containsTestRemote(page Page, remote string) bool {
	for _, message := range page.Messages {
		if message.RemoteID == remote {
			return true
		}
	}
	return false
}

func TestGmailMovesAndFlagsUseLabels(t *testing.T) {
	var paths []string
	gmail := gmailClient{http: &http.Client{Transport: gmailTestTransport(func(r *http.Request) (*http.Response, error) {
		paths = append(paths, r.URL.Path)
		if strings.HasSuffix(r.URL.Path, "/modify") {
			var patch gmailLabelPatch
			if err := json.NewDecoder(r.Body).Decode(&patch); err != nil || len(patch.Add) != 1 || patch.Add[0] != "STARRED" {
				t.Errorf("unexpected flag change: %+v, %v", patch, err)
			}
		}
		return gmailTestResponse(200, `{"id":"abc","labelIds":["INBOX","STARRED"],"historyId":"20","internalDate":"1700000000000"}`), nil
	})}}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	message := Message{RemoteID: "gmail:abc", Mailbox: "Inbox"}
	flag := true
	if err := gmail.patchFlags(ctx, &message, MessagePatch{Flagged: &flag}); err != nil || !message.Flagged {
		t.Fatalf("flag: %+v, %v", message, err)
	}
	if err := gmail.move(ctx, &message, "Trash"); err != nil {
		t.Fatal(err)
	}
	if len(paths) != 2 || !strings.HasSuffix(paths[0], "/abc/modify") || !strings.HasSuffix(paths[1], "/abc/trash") {
		t.Fatalf("wrong message endpoint: %v", paths)
	}
}

func TestGmailReadRetriesRateLimit(t *testing.T) {
	attempts := 0
	client := gmailClient{cooldown: &gmailCooldown{}, http: &http.Client{Transport: gmailTestTransport(func(r *http.Request) (*http.Response, error) {
		attempts++
		if attempts == 1 {
			return gmailTestResponse(403, `{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}`), nil
		}
		return gmailTestResponse(200, `{"historyId":"101"}`), nil
	})}}
	history, err := client.profile(ctx)
	if err != nil || history != "101" || attempts != 2 {
		t.Fatalf("retry did not recover: history=%q attempts=%d error=%v", history, attempts, err)
	}
}

func TestGmailMutationIsNotRetried(t *testing.T) {
	attempts := 0
	client := gmailClient{http: &http.Client{Transport: gmailTestTransport(func(r *http.Request) (*http.Response, error) {
		attempts++
		return gmailTestResponse(503, "{}"), nil
	})}}
	err := client.move(ctx, &Message{RemoteID: "gmail:abc", Mailbox: "Inbox"}, "Trash")
	if err == nil || attempts != 1 {
		t.Fatalf("expected a single write attempt: attempts=%d error=%v", attempts, err)
	}
}

func TestGmailLimitDiagnosticsOnlyUseRecognizedCodes(t *testing.T) {
	body := strings.NewReader(`{"error":{"message":"private mailbox@example.com",
		"errors":[{"reason":"userRateLimitExceeded"},{"reason":"mailbox@example.com"}],
		"details":[{"reason":"RATE_LIMIT_EXCEEDED","metadata":{"account":"private"}}]}}`)
	if got := strings.Join(gmailErrorReasons(body), ","); got != "userRateLimitExceeded,RATE_LIMIT_EXCEEDED" {
		t.Fatalf("unexpected reasons in diagnostics: %q", got)
	}
	for value, want := range map[string]string{
		"300": "300s", "Tue, 17 Nov 2026 04:00:00 GMT": "2026-11-17T04:00:00Z",
		"": "unavailable", "private data": "unavailable",
	} {
		if got := gmailLogRetryAfter(value); got != want {
			t.Errorf("Retry-After %q: got %q, want %q", value, got, want)
		}
	}
}

func TestGmailReadsSharePacing(t *testing.T) {
	cooldown := &gmailCooldown{}
	if err := cooldown.wait(ctx); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	if err := cooldown.wait(ctx); err != nil {
		t.Fatal(err)
	}
	if elapsed := time.Since(start); elapsed < gmailReadInterval-25*time.Millisecond {
		t.Fatalf("the second read started too soon: %s", elapsed)
	}
}

func TestGmailPacingAdaptsToProviderLimits(t *testing.T) {
	c := &gmailCooldown{}
	for i := 0; i < 30; i++ {
		c.succeeded()
	}
	if c.readInterval() >= gmailReadInterval {
		t.Fatal("healthy requests did not increase the rate")
	}
	if !c.pause(time.Second) {
		t.Fatal("first rate limit did not begin a cooldown")
	}
	slower := c.readInterval()
	if slower <= gmailReadInterval || c.pause(time.Second) || c.readInterval() != slower {
		t.Fatalf("simultaneous failures should slow the rate once: %s", c.readInterval())
	}
}
