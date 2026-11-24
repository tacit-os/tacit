// maild runs a local-only mock mail service. It never contacts a mail provider.
// maild serves the local mail cache and optionally connects to an IMAP/SMTP account.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"tacit.local/mailbackend/internal/api"
	"tacit.local/mailbackend/internal/backend"
	"time"
)

func defaults() (string, string, error) {
	home, e := os.UserHomeDir()
	if e != nil {
		return "", "", e
	}
	data := os.Getenv("XDG_DATA_HOME")
	if data == "" {
		data = filepath.Join(home, ".local", "share")
	}
	if runtime.GOOS == "darwin" {
		data = filepath.Join(home, "Library", "Application Support")
	}
	data = filepath.Join(data, "tacit", "mail-mock")
	cache, e := os.UserCacheDir()
	if e != nil {
		return "", "", e
	}
	if x := os.Getenv("XDG_RUNTIME_DIR"); x != "" {
		cache = x
	}
	return data, filepath.Join(cache, "tacit-mail-mock", "mail.sock"), nil
}
func run() error {
	data, socket, e := defaults()
	if e != nil {
		return e
	}
	flag.StringVar(&data, "data-dir", data, "private directory for the SQLite cache")
	flag.StringVar(&socket, "socket", socket, "absolute Unix socket path (private parent directory required)")
	seed := flag.Bool("seed", false, "seed realistic mock mail once")
	localModel := flag.String("local-agent-model", os.Getenv("TACIT_MAIL_LOCAL_MODEL"), "path to a local GGUF model for draft suggestions")
	interval := flag.Duration("worker-interval", 250*time.Millisecond, "outbox polling interval; 0 disables automatic delivery")
	flag.Parse()
	if *interval < 0 {
		return fmt.Errorf("worker interval cannot be negative")
	}
	listener, e := api.Listen(socket)
	if e != nil {
		return e
	}
	defer listener.Close()
	store, e := backend.Open(filepath.Join(data, "mail.sqlite"))
	if e != nil {
		return e
	}
	defer store.Close()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if *seed {
		if e = store.Seed(ctx); e != nil {
			return e
		}
	}
	if e = store.Recover(ctx); e != nil {
		return e
	}
	provider := &backend.MockProvider{Store: store}
	managed := backend.NewManagedAccounts(store, backend.SystemCredentials{})
	transports := backend.AccountProviders{"mock": provider, backend.ManagedIMAP: managed}
	email := os.Getenv("TACIT_MAIL_EMAIL")
	imapAddress := os.Getenv("TACIT_MAIL_IMAP")
	smtpAddress := os.Getenv("TACIT_MAIL_SMTP")
	username := os.Getenv("TACIT_MAIL_USERNAME")
	password := os.Getenv("TACIT_MAIL_PASSWORD")
	if email != "" || imapAddress != "" || smtpAddress != "" || username != "" || password != "" {
		if email == "" || imapAddress == "" || smtpAddress == "" || password == "" {
			return fmt.Errorf("configure TACIT_MAIL_EMAIL, TACIT_MAIL_IMAP, TACIT_MAIL_SMTP and TACIT_MAIL_PASSWORD together")
		}
		if username == "" {
			username = email
		}
		if e = store.ConfigureInternetAccount(ctx, email); e != nil {
			return e
		}
		internet := &backend.InternetProvider{
			Store: store, Email: email, IMAP: imapAddress, SMTP: smtpAddress, Username: username, Password: password,
		}
		transports["imap-smtp"] = internet
	}
	service := backend.NewService(store, transports)
	service.LocalAgentModel = *localModel
	workerDone := make(chan struct{})
	go func() {
		defer close(workerDone)
		if *interval == 0 {
			return
		}
		ticker := time.NewTicker(*interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if _, e := service.Flush(ctx); e != nil && ctx.Err() == nil {
					log.Printf("outbox worker: %v", e)
				}
			}
		}
	}()

	server := &http.Server{Handler: api.New(service, provider, managed), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16 << 10}
	finished := make(chan error, 1)
	go func() { finished <- server.Serve(listener) }()
	log.Printf("mail backend ready; socket=%s database=%s", socket, filepath.Join(data, "mail.sqlite"))
	select {
	case e = <-finished:
		stop()
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		e = server.Shutdown(shutdown)
		cancel()
		if e != nil {
			server.Close()
		}
	}
	stop()
	<-workerDone
	if e == http.ErrServerClosed {
		return nil
	}
	return e
}
func main() {
	if e := run(); e != nil {
		log.Fatal(e)
	}
}
