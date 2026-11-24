package backend

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/emersion/go-smtp"
)

type startTLSTestSession struct{}

func (startTLSTestSession) Reset()                               {}
func (startTLSTestSession) Logout() error                        { return nil }
func (startTLSTestSession) Mail(string, *smtp.MailOptions) error { return smtp.ErrAuthRequired }
func (startTLSTestSession) Rcpt(string, *smtp.RcptOptions) error { return smtp.ErrAuthRequired }
func (startTLSTestSession) Data(io.Reader) error                 { return smtp.ErrAuthRequired }

func TestSMTPStartTLS(t *testing.T) {
	cert := httptest.NewTLSServer(http.NotFoundHandler())
	t.Cleanup(cert.Close)
	roots := x509.NewCertPool()
	roots.AddCert(cert.Certificate())

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := smtp.NewServer(smtp.BackendFunc(func(*smtp.Conn) (smtp.Session, error) {
		return startTLSTestSession{}, nil
	}))
	server.Domain = "localhost"
	server.TLSConfig = &tls.Config{Certificates: cert.TLS.Certificates}
	t.Cleanup(func() { listener.Close(); server.Close() })
	go server.Serve(listener)

	provider := InternetProvider{SMTP: listener.Addr().String(), tlsRoots: roots}
	client, closeConn, err := provider.dialSMTPStartTLS(context.Background(), "127.0.0.1")
	if err != nil {
		t.Fatal(err)
	}
	defer closeConn()
	if state, ok := client.TLSConnectionState(); !ok || len(state.VerifiedChains) == 0 {
		t.Fatal("SMTP connection must use verified TLS")
	}
}
