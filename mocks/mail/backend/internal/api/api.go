// Package api exposes the backend through versioned HTTP over a private Unix socket.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"strconv"
	"strings"
	"tacit.local/mailbackend/internal/backend"
	"time"
)

func metadata(m backend.Message) backend.Message {
	a := append([]backend.Attachment{}, m.Attachments...)
	for i := range a {
		a[i].Data = nil
	}
	m.Attachments = a
	return m
}
func New(s *backend.Service, p *backend.MockProvider, accounts ...*backend.ManagedAccounts) http.Handler {
	mux := http.NewServeMux()
	store := s.Store
	respond := func(w http.ResponseWriter, v any, e error) {
		if e != nil {
			status := 500
			switch {
			case errors.Is(e, backend.ErrTooLarge):
				status = 413
			case errors.Is(e, backend.ErrInvalid):
				status = 400
			case errors.Is(e, backend.ErrNotFound):
				status = 404
			case errors.Is(e, backend.ErrConflict):
				status = 409
			}
			message := http.StatusText(status)
			if status != 500 {
				message = e.Error()
			}
			http.Error(w, message, status)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(v)
	}
	parse := func(w http.ResponseWriter, r *http.Request, v any) bool {
		kind, _, e := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if e != nil || kind != "application/json" {
			http.Error(w, "application/json required", 415)
			return false
		}
		r.Body = http.MaxBytesReader(w, r.Body, 8<<20)
		d := json.NewDecoder(r.Body)
		d.DisallowUnknownFields()
		if e = d.Decode(v); e != nil {
			http.Error(w, "invalid JSON", 400)
			return false
		}
		if e = d.Decode(&struct{}{}); e != io.EOF {
			http.Error(w, "one JSON object required", 400)
			return false
		}
		return true
	}
	imagePolicy := func(w http.ResponseWriter, r *http.Request) {
		var input struct {
			Policy string `json:"policy"`
		}
		if r.Method == http.MethodPut {
			if !parse(w, r, &input) {
				return
			}
			if input.Policy == "" {
				respond(w, nil, backend.ErrInvalid)
				return
			}
		}
		result, err := store.ImagePolicy(r.Context(), r.PathValue("id"), input.Policy)
		respond(w, result, err)
	}
	for _, route := range []string{"/v1/settings/image-policy", "/v1/messages/{id}/image-policy"} {
		mux.HandleFunc("GET "+route, imagePolicy)
		mux.HandleFunc("PUT "+route, imagePolicy)
	}
	mux.HandleFunc("POST /v1/messages/{id}/image-consent", func(w http.ResponseWriter, r *http.Request) {
		err := store.AllowMessageImages(r.Context(), r.PathValue("id"))
		respond(w, map[string]bool{"ok": err == nil}, err)
	})

	mux.HandleFunc("GET /v1/messages/{id}/remote-image", func(w http.ResponseWriter, r *http.Request) {
		id, raw := r.PathValue("id"), r.URL.Query().Get("url")
		mediaType, file, err := store.RemoteImageFile(r.Context(), id, raw)
		onlyCached := false
		for _, directive := range strings.Split(r.Header.Get("Cache-Control"), ",") {
			if strings.EqualFold(strings.TrimSpace(directive), "only-if-cached") {
				onlyCached = true
			}
		}
		allowOrigin := false
		if errors.Is(err, backend.ErrNotFound) {
			var policyErr error
			allowOrigin, policyErr = store.MessageImagesAllowed(r.Context(), id)
			if policyErr != nil {
				respond(w, nil, policyErr)
				return
			}
			// A cache-only probe may inspect permission, but never starts a download.
			w.Header().Set("X-Mail-Image-Origin-Allowed", strconv.FormatBool(allowOrigin))
		}
		allowOrigin = allowOrigin && !onlyCached
		if errors.Is(err, backend.ErrNotFound) && allowOrigin {
			_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(40 * time.Second))
			if _, err = store.CacheRemoteImage(r.Context(), id, raw); err == nil {
				mediaType, file, err = store.RemoteImageFile(r.Context(), id, raw)
			}
		}
		if errors.Is(err, backend.ErrNotFound) && !allowOrigin {
			if _, exists := store.Get(r.Context(), id); exists != nil {
				respond(w, nil, exists)
				return
			}
			w.Header().Set("Cache-Control", "no-store")
			http.Error(w, "image is not cached", http.StatusGatewayTimeout)
			return
		}
		if err != nil {
			respond(w, nil, err)
			return
		}
		defer file.Close()
		w.Header().Set("Content-Type", mediaType)
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		http.ServeContent(w, r, "image", time.Time{}, file)
	})

	mux.HandleFunc("GET /v1/health", func(w http.ResponseWriter, r *http.Request) {
		respond(w, map[string]any{"status": "ok", "api_version": 1, "provider": "mock"}, nil)
	})
	mux.HandleFunc("GET /v1/accounts", func(w http.ResponseWriter, r *http.Request) { v, e := store.Accounts(r.Context()); respond(w, v, e) })
	mux.HandleFunc("POST /v1/agent/draft-suggestion", func(w http.ResponseWriter, r *http.Request) {
		var in backend.DraftSuggestion
		if !parse(w, r, &in) {
			return
		}
		_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(125 * time.Second))
		draft, err := s.SuggestDraft(r.Context(), in)
		if errors.Is(err, backend.ErrLocalModelUnavailable) {
			respond(w, map[string]string{"error": err.Error()}, nil)
			return
		}
		respond(w, map[string]string{"draft": draft}, err)
	})
	mux.HandleFunc("GET /v1/accounts/{id}/folders", func(w http.ResponseWriter, r *http.Request) {
		v, err := s.FolderSettings(r.Context(), r.PathValue("id"), nil)
		respond(w, v, err)
	})
	mux.HandleFunc("PUT /v1/accounts/{id}/folders", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Manual map[string]string `json:"manual"`
		}
		if !parse(w, r, &in) {
			return
		}
		if in.Manual == nil {
			respond(w, nil, backend.ErrInvalid)
			return
		}
		v, err := s.FolderSettings(r.Context(), r.PathValue("id"), in.Manual)
		respond(w, v, err)
	})
	if len(accounts) > 0 && accounts[0] != nil {
		mux.HandleFunc("POST /v1/oauth/google", func(w http.ResponseWriter, r *http.Request) {
			login, err := accounts[0].StartGoogle(r.Context())
			if err != nil {
				respond(w, map[string]string{"error": err.Error()}, nil)
				return
			}
			respond(w, login, nil)
		})
		mux.HandleFunc("GET /v1/oauth/google/{id}", func(w http.ResponseWriter, r *http.Request) {
			respond(w, accounts[0].GoogleStatus(r.PathValue("id")), nil)
		})
		mux.HandleFunc("DELETE /v1/oauth/google/{id}", func(w http.ResponseWriter, r *http.Request) {
			accounts[0].CancelGoogle(r.PathValue("id"))
			respond(w, map[string]bool{"ok": true}, nil)
		})
		mux.HandleFunc("POST /v1/accounts/{id}/reconnect", func(w http.ResponseWriter, r *http.Request) {
			var in struct {
				Password string `json:"password"`
			}
			if !parse(w, r, &in) {
				return
			}
			err := accounts[0].Reconnect(r.Context(), r.PathValue("id"), in.Password)
			switch {
			case err == nil:
				respond(w, map[string]bool{"ok": true}, nil)
			case errors.Is(err, backend.ErrIMAPSetup), errors.Is(err, backend.ErrSMTPSetup), errors.Is(err, backend.ErrCredentialStore):
				respond(w, map[string]string{"error": err.Error()}, nil)
			default:
				respond(w, nil, err)
			}
		})
		mux.HandleFunc("GET /v1/accounts/{id}/disconnect", func(w http.ResponseWriter, r *http.Request) {
			summary, err := accounts[0].DisconnectSummary(r.Context(), r.PathValue("id"))
			respond(w, summary, err)
		})
		mux.HandleFunc("POST /v1/accounts/{id}/disconnect", func(w http.ResponseWriter, r *http.Request) {
			var choice struct {
				Remove *bool `json:"remove_local_copy"`
			}
			if !parse(w, r, &choice) {
				return
			}
			if choice.Remove == nil {
				respond(w, nil, backend.ErrInvalid)
				return
			}
			if *choice.Remove && r.URL.Query().Get("progress") == "1" {
				controller := http.NewResponseController(w)
				if err := controller.SetWriteDeadline(time.Time{}); err != nil && !errors.Is(err, http.ErrNotSupported) {
					respond(w, nil, err)
					return
				}
				w.Header().Set("Content-Type", "application/x-ndjson")
				ctx, cancel := context.WithTimeout(r.Context(), 15*time.Minute)
				defer cancel()
				encoder := json.NewEncoder(w)
				write := func(event any) {
					_ = controller.SetWriteDeadline(time.Now().Add(10 * time.Second))
					if encoder.Encode(event) != nil || controller.Flush() != nil {
						cancel()
					}
					_ = controller.SetWriteDeadline(time.Time{})
				}
				write(map[string]bool{"started": true})
				err := s.DisconnectInternetAccountWithProgress(ctx, accounts[0], r.PathValue("id"), true, func(removed, total int64) {
					write(map[string]int64{"removed": removed, "total": total})
				})
				write(map[string]bool{"done": true, "ok": err == nil})
				return
			}
			err := s.DisconnectInternetAccount(r.Context(), accounts[0], r.PathValue("id"), *choice.Remove)
			respond(w, map[string]bool{"ok": err == nil}, err)
		})
		mux.HandleFunc("POST /v1/accounts/imap", func(w http.ResponseWriter, r *http.Request) {
			var settings backend.InternetAccountSettings
			if !parse(w, r, &settings) {
				return
			}
			account, err := accounts[0].Connect(r.Context(), settings)
			if err == nil {
				respond(w, map[string]any{"account": account}, nil)
				return
			}
			for _, known := range []error{backend.ErrInvalid, backend.ErrConflict, backend.ErrIMAPSetup, backend.ErrSMTPSetup, backend.ErrCredentialStore} {
				if errors.Is(err, known) {
					respond(w, map[string]string{"error": known.Error()}, nil)
					return
				}
			}
			respond(w, nil, err)
		})
	}
	mux.HandleFunc("GET /v1/mailboxes/counts", func(w http.ResponseWriter, r *http.Request) {
		counts, err := store.MailboxCounts(r.Context())
		respond(w, counts, err)
	})
	mux.HandleFunc("GET /v1/messages", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		query := backend.Query{AccountID: q.Get("account_id"), Mailbox: q.Get("mailbox"), Search: q.Get("q")}
		for name, target := range map[string]*int{"limit": &query.Limit, "offset": &query.Offset} {
			if raw := q.Get(name); raw != "" {
				n, e := strconv.Atoi(raw)
				if e != nil {
					respond(w, nil, backend.ErrInvalid)
					return
				}
				*target = n
			}
		}
		if q.Get("view") == "1" {
			v, e := store.ListView(r.Context(), backend.ViewQuery{Query: query, SearchMode: q.Get("search") == "1", GmailCategory: q.Get("gmail_category"), Filter: q.Get("filter"), Sort: q.Get("sort"), Generation: q.Get("generation"), Locale: q.Get("locale"), SelectedID: q.Get("selected_id")})
			respond(w, v, e)
			return
		}
		v, e := store.List(r.Context(), query)
		for i := range v.Messages {
			v.Messages[i] = metadata(v.Messages[i])
			if q.Get("summary") == "1" && v.Messages[i].Mailbox != "Drafts" {
				m := &v.Messages[i]
				for j := range m.Attachments {
					m.Attachments[j].Inline = m.Attachments[j].Inline || strings.Contains(m.BodyHTML, "cid:"+m.Attachments[j].ID)
				}
				m.HasHTML = m.BodyHTML != ""
				m.BodyHTML = ""
				m.BodyParts = nil
				preview := []rune(m.BodyText)
				if len(preview) > 512 {
					m.BodyText = string(preview[:512])
				}
			}
		}
		respond(w, v, e)
	})
	mux.HandleFunc("GET /v1/messages/{id}", func(w http.ResponseWriter, r *http.Request) {
		v, e := store.Get(r.Context(), r.PathValue("id"))
		respond(w, metadata(v), e)
	})
	mux.HandleFunc("POST /v1/messages/{id}/restore-trash-thread", func(w http.ResponseWriter, r *http.Request) {
		respond(w, map[string]bool{"ok": true}, store.RestoreTrashedThread(r.Context(), r.PathValue("id")))
	})
	for route, folder := range map[string]string{"delete-trash-thread": "Trash", "delete-spam-thread": "Spam"} {
		mux.HandleFunc("POST /v1/messages/{id}/"+route, func(w http.ResponseWriter, r *http.Request) {
			var in struct {
				IDs []string `json:"ids"`
			}
			if !parse(w, r, &in) {
				return
			}
			respond(w, map[string]bool{"ok": true}, store.DeleteFolderThread(r.Context(), r.PathValue("id"), in.IDs, folder))
		})
	}
	mux.HandleFunc("DELETE /v1/messages/{id}", func(w http.ResponseWriter, r *http.Request) {
		respond(w, map[string]bool{"ok": true}, store.DeleteTrashedMessage(r.Context(), r.PathValue("id")))
	})
	mux.HandleFunc("PATCH /v1/messages/{id}", func(w http.ResponseWriter, r *http.Request) {
		var patch backend.MessagePatch
		if !parse(w, r, &patch) {
			return
		}
		v, e := store.Patch(r.Context(), r.PathValue("id"), patch)
		respond(w, metadata(v), e)
	})
	// Cache inventory and effective permission only; this endpoint never fetches origins.
	mux.HandleFunc("GET /v1/messages/{id}/image-state", func(w http.ResponseWriter, r *http.Request) {
		m, err := store.Get(r.Context(), r.PathValue("id"))
		if err != nil {
			respond(w, nil, err)
			return
		}
		if err = store.ResolveRemoteImages(r.Context(), &m); err != nil {
			respond(w, nil, err)
			return
		}
		allowed, err := store.MessageImagesAllowed(r.Context(), m.ID)
		respond(w, map[string]any{"cached_images": m.RemoteImages, "origin_allowed": allowed}, err)
	})
	mux.HandleFunc("GET /v1/conversations/{id}", func(w http.ResponseWriter, r *http.Request) {
		v, e := store.Conversation(r.Context(), r.URL.Query().Get("account_id"), r.PathValue("id"))
		for i := range v {
			v[i] = metadata(v[i])
			store.InlineDimensions(r.Context(), &v[i])
			if err := store.ResolveRemoteImages(r.Context(), &v[i]); err != nil {
				respond(w, nil, err)
				return
			}
		}
		respond(w, v, e)
	})
	mux.HandleFunc("POST /v1/conversations/{id}/trash", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Account string `json:"account_id"`
		}
		if !parse(w, r, &in) {
			return
		}
		token, err := store.TrashConversation(r.Context(), in.Account, r.PathValue("id"))
		respond(w, map[string]string{"undo_token": token}, err)
	})
	mux.HandleFunc("POST /v1/conversation-trash/{token}/undo", func(w http.ResponseWriter, r *http.Request) {
		var in struct{}
		if !parse(w, r, &in) {
			return
		}
		respond(w, map[string]bool{"ok": true}, store.UndoConversationTrash(r.Context(), r.PathValue("token")))
	})
	mux.HandleFunc("POST /v1/accounts/{account}/attachments", func(w http.ResponseWriter, r *http.Request) {
		kind, params, e := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if e != nil {
			http.Error(w, "valid Content-Type required", 415)
			return
		}
		if r.ContentLength > backend.MaxAttachmentSize {
			respond(w, nil, backend.ErrTooLarge)
			return
		}
		a, e := store.UploadAttachment(r.Context(), r.PathValue("account"), r.URL.Query().Get("filename"), mime.FormatMediaType(kind, params), r.Body, backend.MaxAttachmentSize)
		if e != nil {
			respond(w, nil, e)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(201)
		json.NewEncoder(w).Encode(a)
	})
	mux.HandleFunc("GET /v1/messages/{id}/attachments/{attachment}", func(w http.ResponseWriter, r *http.Request) {
		a, f, e := store.MessageAttachment(r.Context(), r.PathValue("id"), r.PathValue("attachment"))
		if e != nil {
			respond(w, nil, e)
			return
		}
		defer f.Close()
		w.Header().Set("Content-Type", a.MediaType)
		w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": a.Filename}))
		w.Header().Set("X-Content-Type-Options", "nosniff")
		http.ServeContent(w, r, a.Filename, time.Time{}, f)
	})

	save := func(w http.ResponseWriter, r *http.Request) {
		var m backend.Message
		if !parse(w, r, &m) {
			return
		}
		if r.Method == "PUT" {
			m.ID = r.PathValue("id")
		} else if m.ID != "" {
			respond(w, nil, backend.ErrInvalid)
			return
		}
		if m.AccountID == "" {
			respond(w, nil, backend.ErrInvalid)
			return
		}
		v, e := store.SaveDraft(r.Context(), m)
		if e != nil {
			respond(w, nil, e)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		if r.Method == "POST" {
			w.WriteHeader(201)
		}
		json.NewEncoder(w).Encode(metadata(v))
	}
	mux.HandleFunc("POST /v1/drafts", save)
	mux.HandleFunc("PUT /v1/drafts/{id}", save)
	mux.HandleFunc("POST /v1/send", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			DraftID     string `json:"draft_id"`
			Key         string `json:"idempotency_key"`
			UndoSeconds int    `json:"undo_seconds"`
		}
		if !parse(w, r, &in) {
			return
		}
		v, e := store.QueueDelayed(r.Context(), in.DraftID, in.Key, in.UndoSeconds)
		if e != nil {
			respond(w, nil, e)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(202)
		json.NewEncoder(w).Encode(v)
	})
	mux.HandleFunc("POST /v1/outbox/{id}/undo", func(w http.ResponseWriter, r *http.Request) {
		var in struct{}
		if !parse(w, r, &in) {
			return
		}
		respond(w, map[string]bool{"ok": true}, store.UndoSend(r.Context(), r.PathValue("id")))
	})
	mux.HandleFunc("GET /v1/outbox", func(w http.ResponseWriter, r *http.Request) {
		jobs, err := store.ActiveJobs(r.Context())
		respond(w, map[string]any{"jobs": jobs}, err)
	})
	mux.HandleFunc("GET /v1/outbox/{id}", func(w http.ResponseWriter, r *http.Request) {
		v, e := store.Job(r.Context(), r.PathValue("id"))
		respond(w, v, e)
	})
	mux.HandleFunc("POST /v1/outbox/{id}/retry", func(w http.ResponseWriter, r *http.Request) {
		var in struct{}
		if !parse(w, r, &in) {
			return
		}
		e := store.Retry(r.Context(), r.PathValue("id"))
		respond(w, map[string]bool{"queued": e == nil}, e)
	})
	mux.HandleFunc("POST /v1/sync/wait", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			AccountID string `json:"account_id"`
		}
		if !parse(w, r, &in) {
			return
		}
		e := s.WaitInbox(r.Context(), in.AccountID)
		respond(w, map[string]bool{"ready": e == nil}, e)
	})
	mux.HandleFunc("POST /v1/sync", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			AccountID string `json:"account_id"`
		}
		if !parse(w, r, &in) {
			return
		}
		v, e := s.Sync(r.Context(), in.AccountID)
		if errors.Is(e, backend.ErrGoogleSignInAgain) {
			respond(w, map[string]bool{"google_sign_in_again": true}, nil)
			return
		}
		respond(w, v, e)
	})
	mux.HandleFunc("POST /v1/sync/import", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			AccountID string `json:"account_id"`
		}
		if !parse(w, r, &in) {
			return
		}
		controller := http.NewResponseController(w)
		if err := controller.SetWriteDeadline(time.Time{}); err != nil && !errors.Is(err, http.ErrNotSupported) {
			respond(w, nil, err)
			return
		}
		w.Header().Set("Content-Type", "application/x-ndjson")
		ctx, cancel := context.WithCancel(r.Context())
		defer cancel()
		encoder := json.NewEncoder(w)
		write := func(value any) {
			_ = controller.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if encoder.Encode(value) != nil || controller.Flush() != nil {
				cancel()
			}
			_ = controller.SetWriteDeadline(time.Time{})
		}
		write(map[string]bool{"started": true})
		v, err := s.SyncWithProgress(ctx, in.AccountID, func(done, total int) {
			write(map[string]int{"downloaded": done, "total": total})
		})
		if errors.Is(err, backend.ErrGoogleSignInAgain) {
			write(map[string]any{"done": true, "ok": false, "result": map[string]bool{"google_sign_in_again": true}})
			return
		}
		write(map[string]any{"done": true, "ok": err == nil, "result": v})
	})
	mux.HandleFunc("POST /v1/mock/incoming", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			AccountID string          `json:"account_id"`
			Message   backend.Message `json:"message"`
		}
		if !parse(w, r, &in) {
			return
		}
		e := p.Inject(r.Context(), in.AccountID, in.Message)
		if e != nil {
			respond(w, nil, e)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(201)
		json.NewEncoder(w).Encode(map[string]bool{"accepted": true})
	})
	mux.HandleFunc("POST /v1/mock/fail-next-send", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			AccountID string `json:"account_id"`
		}
		if !parse(w, r, &in) {
			return
		}
		e := p.FailNext(r.Context(), in.AccountID)
		respond(w, map[string]bool{"armed": e == nil}, e)
	})
	mux.HandleFunc("POST /v1/mock/flush", func(w http.ResponseWriter, r *http.Request) {
		var in struct{}
		if !parse(w, r, &in) {
			return
		}
		n, e := s.Flush(r.Context())
		respond(w, map[string]int{"processed": n}, e)
	})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.Header.Get("Origin") != "" {
			http.Error(w, "browser origins are not supported", 403)
			return
		}
		mux.ServeHTTP(w, r)
	})
}
