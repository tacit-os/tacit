package backend

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"
)

func TestGoogleOAuthLoopback(t *testing.T) {
	var challenge, redirect string
	endpoint := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Error(err)
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		verifierHash := sha256.Sum256([]byte(r.PostForm.Get("code_verifier")))
		if base64.RawURLEncoding.EncodeToString(verifierHash[:]) != challenge ||
			r.PostForm.Get("redirect_uri") != redirect || r.PostForm.Get("code") != "test-code" {
			t.Error("authorization code was not bound to the original redirect and PKCE challenge")
		}
		io.WriteString(w, `{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600}`)
	}))
	defer endpoint.Close()

	oauth := GoogleOAuth{ClientID: "test-client", tokenURL: endpoint.URL}
	tokens, err := oauth.Authorize(context.Background(), func(raw string) error {
		uri, err := url.Parse(raw)
		if err != nil {
			return err
		}
		q := uri.Query()
		challenge, redirect = q.Get("code_challenge"), q.Get("redirect_uri")
		if uri.Host != "accounts.google.com" || q.Get("client_id") != "test-client" ||
			q.Get("scope") != googleMailScope+" openid email" || q.Get("code_challenge_method") != "S256" ||
			q.Get("access_type") != "offline" || q.Get("state") == "" {
			t.Fatal("unexpected browser authorization request")
		}
		makeCallback := func(state string, expected int) {
			query := url.Values{"state": {state}, "code": {"test-code"}}
			response, err := http.Get(redirect + "?" + query.Encode())
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			io.Copy(io.Discard, response.Body)
			if response.StatusCode != expected {
				t.Fatalf("callback status: got %d, want %d", response.StatusCode, expected)
			}
		}
		makeCallback("wrong-state", http.StatusBadRequest)
		makeCallback(q.Get("state"), http.StatusOK)
		return nil
	})
	if err != nil || tokens.AccessToken != "test-access" || tokens.RefreshToken != "test-refresh" {
		t.Fatalf("authorization failed: %v", err)
	}
}

func TestGoogleOAuthFinishesBrowserResponseOnDenial(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	browserURL := make(chan string, 1)
	finished := make(chan error, 1)
	go func() {
		oauth := GoogleOAuth{ClientID: "test-client"}
		_, err := oauth.Authorize(ctx, func(address string) error {
			browserURL <- address
			return nil
		})
		finished <- err
	}()

	var address string
	select {
	case address = <-browserURL:
	case <-ctx.Done():
		t.Fatal("callback listener did not start")
	}
	authorization, err := url.Parse(address)
	if err != nil {
		t.Fatal(err)
	}
	query := url.Values{"state": {authorization.Query().Get("state")}, "error": {"access_denied"}}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, authorization.Query().Get("redirect_uri")+"?"+query.Encode(), nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil || response.StatusCode != http.StatusOK || string(body) != "You can now return to Tacit Mail." {
		t.Fatalf("incomplete browser response: status=%d, error=%v", response.StatusCode, err)
	}
	if err := <-finished; !errors.Is(err, ErrGoogleOAuthDenied) {
		t.Fatalf("unexpected sign-in result: %v", err)
	}
}

func TestGoogleOAuthRefresh(t *testing.T) {
	endpoint := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil || r.PostForm.Get("grant_type") != "refresh_token" {
			t.Error("invalid refresh request")
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if r.PostForm.Get("refresh_token") == "expired" {
			w.WriteHeader(http.StatusBadRequest)
			io.WriteString(w, `{"error":"invalid_grant"}`)
			return
		}
		io.WriteString(w, `{"access_token":"renewed","expires_in":3600}`)
	}))
	defer endpoint.Close()

	oauth := GoogleOAuth{ClientID: "test-client", tokenURL: endpoint.URL}
	tokens, err := oauth.Refresh(context.Background(), "keep-this-token")
	if err != nil || tokens.AccessToken != "renewed" || tokens.RefreshToken != "keep-this-token" {
		t.Fatalf("refresh failed: %v", err)
	}
	if _, err := oauth.Refresh(context.Background(), "expired"); !errors.Is(err, ErrGoogleSignInAgain) {
		t.Fatalf("expired token should require sign-in: %v", err)
	}
}
