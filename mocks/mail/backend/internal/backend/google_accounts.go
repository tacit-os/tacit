package backend

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/emersion/go-imap/v2/imapclient"
	"github.com/emersion/go-sasl"
)

const googleDesktopClient = "468040953880-05kctapnnebu4e1o04t9n9nlmkipqv59.apps.googleusercontent.com"

type googleLogin struct {
	ID      string   `json:"id"`
	URL     string   `json:"url,omitempty"`
	Status  string   `json:"status"`
	Account *Account `json:"account,omitempty"`
	Error   string   `json:"error,omitempty"`
	cancel  context.CancelFunc
}

type cachedGoogleToken struct {
	access  string
	refresh string
	expires time.Time
}

func googleOAuthConfig() (GoogleOAuth, error) {
	id := os.Getenv("TACIT_GOOGLE_CLIENT_ID")
	if id == "" {
		id = googleDesktopClient
	}
	config := GoogleOAuth{ClientID: id, ClientSecret: os.Getenv("TACIT_GOOGLE_CLIENT_SECRET")}
	if path := os.Getenv("TACIT_GOOGLE_CREDENTIALS"); path != "" {
		raw, err := os.ReadFile(path)
		if err != nil {
			return GoogleOAuth{}, ErrGoogleOAuthFailed
		}
		var file struct {
			Installed struct {
				ClientID     string `json:"client_id"`
				ClientSecret string `json:"client_secret"`
			} `json:"installed"`
		}
		if json.Unmarshal(raw, &file) != nil || file.Installed.ClientID != id {
			return GoogleOAuth{}, ErrGoogleOAuthFailed
		}
		config.ClientSecret = file.Installed.ClientSecret
	}
	return config, nil
}

func (m *ManagedAccounts) StartGoogle(ctx context.Context) (googleLogin, error) {
	id, err := randomOAuthValue()
	if err != nil {
		return googleLogin{}, ErrGoogleOAuthFailed
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), googleSignInTimeout)
	login := &googleLogin{ID: id, Status: "pending", cancel: cancel}
	m.googleMu.Lock()
	if m.googleLogin != nil && m.googleLogin.Status == "pending" {
		m.googleMu.Unlock()
		cancel()
		return googleLogin{}, ErrConflict
	}
	m.googleLogin = login
	m.googleMu.Unlock()

	ready := make(chan string, 1)
	go func() {
		defer cancel()
		account, err := m.completeGoogle(ctx, func(address string) error {
			ready <- address
			return nil
		})
		m.googleMu.Lock()
		defer m.googleMu.Unlock()
		if login.Status != "pending" {
			return
		}
		if err != nil {
			login.Status = "failed"
			login.Error = ErrGoogleOAuthFailed.Error()
			for _, known := range []error{ErrGoogleOAuthTimeout, ErrGoogleOAuthDenied, ErrGoogleSignInAgain, ErrConflict, ErrIMAPSetup, ErrSMTPSetup, ErrCredentialStore} {
				if errors.Is(err, known) {
					login.Error = known.Error()
					break
				}
			}
			return
		}
		login.Status, login.Account = "connected", &account
	}()
	select {
	case address := <-ready:
		return googleLogin{ID: id, URL: address, Status: "pending"}, nil
	case <-ctx.Done():
		return googleLogin{}, ErrGoogleOAuthFailed
	}
}

func (m *ManagedAccounts) GoogleStatus(id string) googleLogin {
	m.googleMu.Lock()
	defer m.googleMu.Unlock()
	if m.googleLogin == nil || m.googleLogin.ID != id {
		return googleLogin{Status: "failed", Error: ErrGoogleOAuthFailed.Error()}
	}
	return *m.googleLogin
}

func (m *ManagedAccounts) CancelGoogle(id string) {
	m.googleMu.Lock()
	defer m.googleMu.Unlock()
	if m.googleLogin != nil && m.googleLogin.ID == id && m.googleLogin.Status == "pending" {
		m.googleLogin.cancel()
	}
}

func (m *ManagedAccounts) completeGoogle(ctx context.Context, open func(string) error) (Account, error) {
	config, err := googleOAuthConfig()
	if err != nil {
		return Account{}, err
	}
	tokens, err := config.Authorize(ctx, open)
	if err != nil {
		return Account{}, err
	}
	email, err := googleEmail(ctx, tokens.AccessToken)
	if err != nil {
		return Account{}, err
	}
	return m.connect(ctx, InternetAccountSettings{
		Email: email, IMAP: "imap.gmail.com:993", SMTP: "smtp.gmail.com:465", GoogleRefreshToken: tokens.RefreshToken,
	}, tokens.AccessToken)
}

func googleEmail(ctx context.Context, token string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://openidconnect.googleapis.com/v1/userinfo", nil)
	if err != nil {
		return "", ErrGoogleOAuthFailed
	}
	req.Header.Set("Authorization", "Bearer "+token)
	client := googleHTTPClient()
	response, err := client.Do(req)
	if err != nil {
		return "", ErrGoogleOAuthFailed
	}
	defer response.Body.Close()
	var user struct {
		Email    string `json:"email"`
		Verified bool   `json:"email_verified"`
	}
	if response.StatusCode != http.StatusOK ||
		json.NewDecoder(io.LimitReader(response.Body, 64<<10)).Decode(&user) != nil ||
		!user.Verified || user.Email == "" {
		return "", ErrGoogleOAuthFailed
	}
	return user.Email, nil
}

func googleHTTPClient() *http.Client {
	return &http.Client{Timeout: 15 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
}

func (m *ManagedAccounts) refreshGmailAccess(ctx context.Context, id, rejected string) (string, error) {
	m.googleMu.Lock()
	defer m.googleMu.Unlock()

	raw, err := m.secrets.Get(ctx, id)
	if err != nil {
		return "", ErrCredentialStore
	}
	var settings InternetAccountSettings
	if json.Unmarshal(raw, &settings) != nil || settings.GoogleRefreshToken == "" {
		return "", ErrCredentialStore
	}
	if m.googleTokens[id].access == rejected {
		delete(m.googleTokens, id)
	}
	return m.googleAccess(ctx, id, settings)
}

// The caller holds googleMu while reading or replacing the refresh token.
func (m *ManagedAccounts) googleAccess(ctx context.Context, id string, settings InternetAccountSettings) (string, error) {
	cached := m.googleTokens[id]
	if cached.refresh == settings.GoogleRefreshToken && time.Until(cached.expires) > time.Minute {
		return cached.access, nil
	}
	config, err := googleOAuthConfig()
	if err != nil {
		return "", err
	}
	tokens, err := config.Refresh(ctx, settings.GoogleRefreshToken)
	if err != nil {
		return "", err
	}
	if tokens.RefreshToken != settings.GoogleRefreshToken {
		settings.GoogleRefreshToken = tokens.RefreshToken
		raw, err := json.Marshal(settings)
		if err != nil || m.secrets.Put(ctx, id, raw) != nil {
			return "", ErrCredentialStore
		}
	}
	if m.googleTokens == nil {
		m.googleTokens = make(map[string]cachedGoogleToken)
	}
	m.googleTokens[id] = cachedGoogleToken{tokens.AccessToken, tokens.RefreshToken, time.Now().Add(time.Duration(tokens.ExpiresIn) * time.Second)}
	return tokens.AccessToken, nil
}

func (m *ManagedAccounts) disconnectCredential(ctx context.Context, id string) error {
	m.googleMu.Lock()
	defer m.googleMu.Unlock()
	if raw, err := m.secrets.Get(ctx, id); err == nil {
		var settings InternetAccountSettings
		if json.Unmarshal(raw, &settings) == nil && settings.GoogleRefreshToken != "" {
			form := url.Values{"token": {settings.GoogleRefreshToken}}
			req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://oauth2.googleapis.com/revoke", strings.NewReader(form.Encode()))
			if err != nil {
				return err
			}
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			response, err := googleHTTPClient().Do(req)
			if err != nil {
				return err
			}
			response.Body.Close()
			if response.StatusCode != http.StatusOK && response.StatusCode != http.StatusBadRequest {
				return ErrGoogleOAuthFailed
			}
		}
	}
	delete(m.googleTokens, id)
	return m.secrets.Delete(ctx, id)
}

type xoauth2Client struct{ username, token string }

func (c xoauth2Client) Start() (string, []byte, error) {
	return "XOAUTH2", []byte("user=" + c.username + "\x01auth=Bearer " + c.token + "\x01\x01"), nil
}
func (c xoauth2Client) Next([]byte) ([]byte, error) { return []byte{}, nil }

func (p *InternetProvider) smtpAuth() sasl.Client {
	if p.accessToken != "" {
		return xoauth2Client{p.Username, p.accessToken}
	}
	return sasl.NewPlainClient("", p.Username, p.Password)
}

func (p *InternetProvider) authenticateIMAP(client *imapclient.Client) error {
	if p.accessToken != "" {
		return client.Authenticate(xoauth2Client{p.Username, p.accessToken})
	}
	return client.Login(p.Username, p.Password).Wait()
}
