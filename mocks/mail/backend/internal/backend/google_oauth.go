package backend

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	googleAuthorizeURL  = "https://accounts.google.com/o/oauth2/v2/auth"
	googleTokenURL      = "https://oauth2.googleapis.com/token"
	googleSignInTimeout = 10 * time.Minute
	googleMailScope     = "https://mail.google.com/"
)

var (
	ErrGoogleOAuthTimeout = errors.New("google_oauth_timeout")
	ErrGoogleOAuthDenied  = errors.New("google_oauth_denied")
	ErrGoogleOAuthFailed  = errors.New("google_oauth_failed")
	ErrGoogleSignInAgain  = errors.New("google_sign_in_again")
)

type GoogleOAuth struct {
	ClientID     string
	ClientSecret string
	tokenURL     string
}

type GoogleTokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
}

func randomOAuthValue() (string, error) {
	var bytes [32]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes[:]), nil
}

// Authorize passes only the browser URL to open. The callback and tokens stay in maild.
func (g GoogleOAuth) Authorize(ctx context.Context, open func(string) error) (GoogleTokens, error) {
	if g.ClientID == "" {
		return GoogleTokens{}, ErrGoogleOAuthFailed
	}
	ctx, cancel := context.WithTimeout(ctx, googleSignInTimeout)
	defer cancel()
	state, err := randomOAuthValue()
	if err != nil {
		return GoogleTokens{}, err
	}
	verifier, err := randomOAuthValue()
	if err != nil {
		return GoogleTokens{}, err
	}
	listener, err := (&net.ListenConfig{}).Listen(ctx, "tcp4", "127.0.0.1:0")
	if err != nil {
		return GoogleTokens{}, err
	}
	redirect := "http://" + listener.Addr().String() + "/"
	type callback struct {
		code string
		err  error
	}
	result := make(chan callback, 1)
	var accepted sync.Once
	server := &http.Server{
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      5 * time.Second,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-store")
			if r.Method != http.MethodGet || r.URL.Path != "/" || r.Host != listener.Addr().String() {
				http.NotFound(w, r)
				return
			}
			q := r.URL.Query()
			if subtle.ConstantTimeCompare([]byte(q.Get("state")), []byte(state)) != 1 {
				http.Error(w, "Invalid sign-in request.", http.StatusBadRequest)
				return
			}
			reply := callback{code: q.Get("code")}
			switch {
			case q.Get("error") == "access_denied":
				reply.err = ErrGoogleOAuthDenied
			case q.Get("error") != "" || reply.code == "":
				reply.err = ErrGoogleOAuthFailed
			}
			accepted.Do(func() {
				_, _ = io.WriteString(w, "You can now return to Tacit Mail.")
				result <- reply
			})
		}),
	}
	go server.Serve(listener)
	defer func() {
		// A fast token response must not interrupt the browser response.
		shutdownCtx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		if server.Shutdown(shutdownCtx) != nil {
			_ = server.Close()
		}
		_ = listener.Close()
	}()
	challenge := sha256.Sum256([]byte(verifier))
	query := url.Values{
		"client_id": {g.ClientID}, "redirect_uri": {redirect},
		"response_type": {"code"}, "scope": {googleMailScope + " openid email"},
		"access_type": {"offline"}, "prompt": {"consent select_account"},
		"state": {state}, "code_challenge_method": {"S256"},
		"code_challenge": {base64.RawURLEncoding.EncodeToString(challenge[:])},
	}
	if err := open(googleAuthorizeURL + "?" + query.Encode()); err != nil {
		return GoogleTokens{}, err
	}
	select {
	case <-ctx.Done():
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return GoogleTokens{}, ErrGoogleOAuthTimeout
		}
		return GoogleTokens{}, ctx.Err()
	case reply := <-result:
		if reply.err != nil {
			return GoogleTokens{}, reply.err
		}
		tokens, err := g.exchange(ctx, url.Values{
			"grant_type": {"authorization_code"}, "code": {reply.code},
			"redirect_uri": {redirect}, "code_verifier": {verifier},
		})
		if err == nil && tokens.RefreshToken == "" {
			return GoogleTokens{}, ErrGoogleOAuthFailed
		}
		return tokens, err
	}
}

func (g GoogleOAuth) Refresh(ctx context.Context, token string) (GoogleTokens, error) {
	if token == "" {
		return GoogleTokens{}, ErrGoogleSignInAgain
	}
	tokens, err := g.exchange(ctx, url.Values{
		"grant_type": {"refresh_token"}, "refresh_token": {token},
	})
	if err == nil && tokens.RefreshToken == "" {
		tokens.RefreshToken = token
	}
	return tokens, err
}

func (g GoogleOAuth) exchange(ctx context.Context, form url.Values) (GoogleTokens, error) {
	endpoint := g.tokenURL
	if endpoint == "" {
		endpoint = googleTokenURL
	}
	form.Set("client_id", g.ClientID)
	if g.ClientSecret != "" {
		form.Set("client_secret", g.ClientSecret)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return GoogleTokens{}, ErrGoogleOAuthFailed
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	client := &http.Client{
		Timeout:       15 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	res, err := client.Do(req)
	if err != nil {
		return GoogleTokens{}, ErrGoogleOAuthFailed
	}
	defer res.Body.Close()
	var response struct {
		GoogleTokens
		Error string `json:"error"`
	}
	if json.NewDecoder(io.LimitReader(res.Body, 64<<10)).Decode(&response) != nil {
		return GoogleTokens{}, ErrGoogleOAuthFailed
	}
	if response.Error == "invalid_grant" && form.Get("grant_type") == "refresh_token" {
		return GoogleTokens{}, ErrGoogleSignInAgain
	}
	if res.StatusCode != http.StatusOK || response.AccessToken == "" || response.ExpiresIn <= 0 {
		return GoogleTokens{}, ErrGoogleOAuthFailed
	}
	return response.GoogleTokens, nil
}
