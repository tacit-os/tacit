package backend

import (
	"context"
	"crypto/x509"
	"encoding/json"
	"errors"
	"net"
	"net/mail"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

const ManagedIMAP = "managed-imap"

var (
	ErrIMAPSetup       = errors.New("imap_setup_failed")
	ErrSMTPSetup       = errors.New("smtp_setup_failed")
	ErrCredentialStore = errors.New("credential_store_failed")
)

type InternetAccountSettings struct {
	Email              string `json:"email"`
	Username           string `json:"username"`
	IMAP               string `json:"imap"`
	SMTP               string `json:"smtp"`
	Password           string `json:"password,omitempty"`
	GoogleRefreshToken string `json:"google_refresh_token,omitempty"`
}

// CredentialStore uses the current desktop user's system secret store.
type CredentialStore interface {
	Get(context.Context, string) ([]byte, error)
	Put(context.Context, string, []byte) error
	Delete(context.Context, string) error
}

type ManagedAccounts struct {
	store        *Store
	secrets      CredentialStore
	tlsRoots     *x509.CertPool
	mu           sync.Mutex
	googleMu     sync.Mutex
	googleLogin  *googleLogin
	googleTokens map[string]cachedGoogleToken
}

func NewManagedAccounts(store *Store, secrets CredentialStore) *ManagedAccounts {
	return NewManagedAccountsWithTLSRoots(store, secrets, nil)
}

// NewManagedAccountsWithTLSRoots uses an explicit CA pool for managed transports.
// A nil pool uses the system roots and still verifies the server name.
func NewManagedAccountsWithTLSRoots(store *Store, secrets CredentialStore, roots *x509.CertPool) *ManagedAccounts {
	return &ManagedAccounts{store: store, secrets: secrets, tlsRoots: roots}
}

func validMailEndpoint(value string) bool {
	host, port, err := net.SplitHostPort(value)
	if err != nil || host == "" || strings.ContainsAny(host, " /\\\t\r\n") {
		return false
	}
	n, err := strconv.Atoi(port)
	return err == nil && n >= 1 && n <= 65535
}

func (m *ManagedAccounts) provider(settings InternetAccountSettings) *InternetProvider {
	return &InternetProvider{Store: m.store, tlsRoots: m.tlsRoots, Email: settings.Email, Username: settings.Username,
		IMAP: settings.IMAP, SMTP: settings.SMTP, Password: settings.Password}
}

func (m *ManagedAccounts) Connect(ctx context.Context, settings InternetAccountSettings) (Account, error) {
	settings.GoogleRefreshToken = ""
	return m.connect(ctx, settings, "")
}

func (m *ManagedAccounts) connect(ctx context.Context, settings InternetAccountSettings, accessToken string) (Account, error) {
	settings.Email = strings.TrimSpace(settings.Email)
	settings.Username = strings.TrimSpace(settings.Username)
	if settings.Username == "" {
		settings.Username = settings.Email
	}
	address, err := mail.ParseAddress(settings.Email)
	if err != nil || address.Address != settings.Email || (settings.Password == "" && accessToken == "") ||
		!validMailEndpoint(settings.IMAP) || !validMailEndpoint(settings.SMTP) {
		return Account{}, ErrInvalid
	}
	checkCtx, cancel := context.WithTimeout(ctx, 22*time.Second)
	defer cancel()
	provider := m.provider(settings)
	provider.accessToken = accessToken
	if err := provider.checkSetup(checkCtx); err != nil {
		return Account{}, err
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	account := Account{ID: "managed-imap-" + strings.ToLower(settings.Email), Name: settings.Email,
		Email: settings.Email, Provider: ManagedIMAP}
	previous, err := m.store.Account(ctx, account.ID)
	if err == nil && previous.Provider == ManagedIMAP && settings.GoogleRefreshToken != "" {
		value, err := json.Marshal(settings)
		if err != nil {
			return Account{}, err
		}
		m.googleMu.Lock()
		defer m.googleMu.Unlock()
		if m.secrets.Put(ctx, previous.ID, value) != nil {
			return Account{}, ErrCredentialStore
		}
		delete(m.googleTokens, previous.ID)
		return previous, nil
	}
	if err == nil && previous.Provider != OfflineIMAP {
		return Account{}, ErrConflict
	}
	if err != nil && !errors.Is(err, ErrNotFound) {
		return Account{}, err
	}
	account.ImportPending = errors.Is(err, ErrNotFound) || previous.ImportPending
	value, err := json.Marshal(settings)
	if err != nil {
		return Account{}, err
	}
	if err := m.secrets.Put(ctx, account.ID, value); err != nil {
		return Account{}, ErrCredentialStore
	}
	err = m.store.saveManagedAccount(ctx, account)
	if err != nil {
		cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
		defer cancel()
		if m.secrets.Delete(cleanup, account.ID) != nil {
			return Account{}, ErrCredentialStore
		}
		return Account{}, err
	}
	return account, nil
}

func (s *Store) saveManagedAccount(ctx context.Context, account Account) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `INSERT INTO accounts(id,name,email,provider) VALUES(?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET name=excluded.name,email=excluded.email,provider=excluded.provider`,
		account.ID, account.Name, account.Email, account.Provider); err != nil {
		return err
	}
	if account.ImportPending {
		if _, err := tx.ExecContext(ctx, "INSERT OR IGNORE INTO metadata(key,value) VALUES(?,'1')", pendingImportKey+account.ID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (m *ManagedAccounts) transport(ctx context.Context, account Account) (*InternetProvider, error) {
	m.googleMu.Lock()
	defer m.googleMu.Unlock()
	value, err := m.secrets.Get(ctx, account.ID)
	if err != nil {
		return nil, ErrCredentialStore
	}
	var settings InternetAccountSettings
	if json.Unmarshal(value, &settings) != nil || settings.Email != account.Email || (settings.Password == "" && settings.GoogleRefreshToken == "") {
		return nil, ErrCredentialStore
	}
	provider := m.provider(settings)
	if settings.GoogleRefreshToken != "" {
		token, err := m.googleAccess(ctx, account.ID, settings)
		if err != nil {
			return nil, err
		}
		provider.accessToken = token
		provider.refreshGmailToken = func(ctx context.Context, rejected string) (string, error) {
			return m.refreshGmailAccess(ctx, account.ID, rejected)
		}
	}
	return provider, nil
}

// Reconnect checks the new app password against both servers before replacing
// the credential. The account ID and local caches are kept.
func (m *ManagedAccounts) Reconnect(ctx context.Context, id, password string) error {
	if password == "" {
		return ErrInvalid
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	account, err := m.store.Account(ctx, id)
	if err != nil {
		return err
	}
	if account.Provider != ManagedIMAP {
		return ErrConflict
	}
	provider, err := m.transport(ctx, account)
	if err != nil {
		return err
	}
	if provider.accessToken != "" {
		return ErrInvalid
	}
	provider.Password = password
	checkCtx, cancel := context.WithTimeout(ctx, 22*time.Second)
	defer cancel()
	if err := provider.checkSetup(checkCtx); err != nil {
		return err
	}
	raw, err := json.Marshal(InternetAccountSettings{Email: provider.Email, Username: provider.Username,
		IMAP: provider.IMAP, SMTP: provider.SMTP, Password: password})
	if err != nil {
		return err
	}
	if err := m.secrets.Put(ctx, id, raw); err != nil {
		return ErrCredentialStore
	}
	return nil
}

func (m *ManagedAccounts) Receive(ctx context.Context, a Account, cursor string) (Batch, error) {
	p, err := m.transport(ctx, a)
	if err != nil {
		return Batch{}, err
	}
	return p.Receive(ctx, a, cursor)
}

func (m *ManagedAccounts) Send(ctx context.Context, a Account, message Message, key string) (Receipt, error) {
	p, err := m.transport(ctx, a)
	if err != nil {
		return Receipt{}, err
	}
	return p.Send(ctx, a, message, key)
}

func (p *InternetProvider) checkSetup(ctx context.Context) error {
	if p.accessToken != "" {
		if _, err := p.gmail().profile(ctx); err != nil {
			return err
		}
	} else if err := p.checkIMAP(ctx); err != nil {
		return ErrIMAPSetup
	}
	client, closeConn, err := p.dialSMTP(ctx)
	if err != nil {
		return ErrSMTPSetup
	}
	defer closeConn()
	if err := client.Auth(p.smtpAuth()); err != nil {
		return ErrSMTPSetup
	}
	return nil
}

func (p *InternetProvider) checkIMAP(ctx context.Context) error {
	conn, closeConn, err := p.dialMail(ctx, p.IMAP)
	if err != nil {
		return err
	}
	defer closeConn()
	client := imapclient.New(conn, nil)
	if err = p.authenticateIMAP(client); err != nil {
		return err
	}
	_, err = client.Select("INBOX", &imap.SelectOptions{ReadOnly: true}).Wait()
	return err
}
