package backend

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"html"
	"io"
	"mime"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const maxRemoteImageSize = 20 << 20

type RemoteImage struct {
	URL    string `json:"url"`
	Source string `json:"source"`
}

func (s *Store) initRemoteImages() error {
	var version int
	if err := s.db.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.Exec(`
		CREATE TABLE IF NOT EXISTS remote_image_grants (
			message_id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE);
		CREATE TABLE IF NOT EXISTS remote_images (
			message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
			url TEXT NOT NULL, digest TEXT NOT NULL, media_type TEXT NOT NULL,
			PRIMARY KEY(message_id,url));
		CREATE TABLE IF NOT EXISTS remote_image_garbage (digest TEXT PRIMARY KEY);
		CREATE TRIGGER IF NOT EXISTS remove_remote_image AFTER DELETE ON remote_images BEGIN
			INSERT OR IGNORE INTO remote_image_garbage VALUES(old.digest);
		END;
        CREATE TRIGGER IF NOT EXISTS replace_remote_image AFTER UPDATE OF digest ON remote_images
        WHEN old.digest != new.digest BEGIN
            INSERT OR IGNORE INTO remote_image_garbage VALUES(old.digest);
        END;
        `)
	if err != nil {
		return err
	}
	// Version 5 treated every download (including automatic ones) as consent.
	// Keep all image files, but do not turn those rows into explicit permissions.
	if version < 6 {
		if _, err := tx.Exec("DELETE FROM remote_image_grants; PRAGMA user_version=6;"); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// The private IPC API may fetch only HTTPS URLs that occur in this message.
func remoteImageURL(m Message, raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil ||
		(u.Port() != "" && u.Port() != "443") || len(raw) > 8192 ||
		!strings.Contains(html.UnescapeString(m.BodyHTML), raw) {
		return nil, ErrInvalid
	}
	return u, nil
}

func remoteImageHTTPClient() *http.Client {
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	transport := &http.Transport{
		ForceAttemptHTTP2:     true,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 15 * time.Second,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(address)
			if err != nil {
				return nil, err
			}
			addresses, err := net.DefaultResolver.LookupIPAddr(ctx, host)
			if err != nil {
				return nil, err
			}
			for _, address := range addresses {
				ip := address.IP
				if !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() ||
					ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
					return nil, ErrInvalid
				}
			}
			for _, address := range addresses {
				conn, err := dialer.DialContext(ctx, network, net.JoinHostPort(address.IP.String(), port))
				if err == nil {
					return conn, nil
				}
			}
			return nil, fmt.Errorf("remote image connection failed")
		},
	}
	return &http.Client{Transport: transport, Timeout: 30 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 || req.URL.Scheme != "https" || req.URL.User != nil ||
				(req.URL.Port() != "" && req.URL.Port() != "443") {
				return ErrInvalid
			}
			return nil
		}}
}

func (s *Store) CacheRemoteImage(ctx context.Context, messageID, raw string) (RemoteImage, error) {
	message, err := s.Get(ctx, messageID)
	if err != nil {
		return RemoteImage{}, err
	}
	u, err := remoteImageURL(message, raw)
	if err != nil {
		return RemoteImage{}, err
	}

	if image, err := s.cachedRemoteImage(ctx, messageID, raw); err == nil {
		return image, nil
	} else if !errors.Is(err, ErrNotFound) && !errors.Is(err, os.ErrNotExist) {
		return RemoteImage{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return RemoteImage{}, err
	}
	req.Header.Set("Accept", "image/*")
	response, err := s.remoteImagesHTTP.Do(req)
	if err != nil {
		return RemoteImage{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return RemoteImage{}, fmt.Errorf("image HTTP %d", response.StatusCode)
	}
	if response.ContentLength > maxRemoteImageSize {
		return RemoteImage{}, ErrTooLarge
	}
	data, err := io.ReadAll(io.LimitReader(contextReader{ctx, response.Body}, maxRemoteImageSize+1))
	if err != nil {
		return RemoteImage{}, err
	}
	if len(data) > maxRemoteImageSize {
		return RemoteImage{}, ErrTooLarge
	}
	mediaType, _, _ := mime.ParseMediaType(response.Header.Get("Content-Type"))
	if !strings.HasPrefix(mediaType, "image/") {
		mediaType = http.DetectContentType(data)
	}
	switch mediaType {
	case "image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/svg+xml", "image/x-icon", "image/vnd.microsoft.icon":
	default:
		return RemoteImage{}, ErrInvalid
	}
	temp, digest, _, err := s.stageBlob(ctx, bytes.NewReader(data), maxRemoteImageSize)
	if err != nil {
		return RemoteImage{}, err
	}
	defer os.Remove(temp)
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return RemoteImage{}, err
	}
	defer tx.Rollback()
	current, err := read(ctx, tx, messageID)
	if err != nil {
		return RemoteImage{}, err
	}
	if current.AccountID != message.AccountID || current.BodyHTML != message.BodyHTML {
		return RemoteImage{}, ErrConflict
	}
	if err := publishBlob(temp, digest); err != nil {
		return RemoteImage{}, err
	}
	// A missing blob can be repaired without losing the message's consent.
	if _, err := tx.ExecContext(ctx, `INSERT INTO remote_images VALUES(?,?,?,?)
        ON CONFLICT(message_id,url) DO UPDATE SET digest=excluded.digest,media_type=excluded.media_type`,
		messageID, raw, digest, mediaType); err != nil {
		return RemoteImage{}, err
	}
	if _, err := tx.ExecContext(ctx, "INSERT OR IGNORE INTO remote_image_garbage VALUES(?)", digest); err != nil {
		return RemoteImage{}, err
	}
	if err := tx.Commit(); err != nil {
		return RemoteImage{}, err
	}
	return s.cachedRemoteImage(ctx, messageID, raw)
}

func (s *Store) cachedRemoteImage(ctx context.Context, messageID, raw string) (RemoteImage, error) {
	var digest, mediaType string
	err := s.db.QueryRowContext(ctx, "SELECT digest,media_type FROM remote_images WHERE message_id=? AND url=?",
		messageID, raw).Scan(&digest, &mediaType)
	if err != nil {
		return RemoteImage{}, mapped(err)
	}
	return s.remoteImageData(messageID, raw, digest, mediaType)
}

func (s *Store) remoteImageData(messageID, raw, digest, mediaType string) (RemoteImage, error) {
	if len(digest) != 64 || strings.Trim(digest, "0123456789abcdef") != "" {
		return RemoteImage{}, ErrInvalid
	}
	_, err := os.Stat(filepath.Join(s.path+".blobs", digest))
	if err != nil {
		return RemoteImage{}, err
	}
	return RemoteImage{raw, "tacit-image://mail/v1/messages/" + url.PathEscape(messageID) + "/remote-image?url=" + url.QueryEscape(raw)}, nil
}

// Resolve only image URLs. Hyperlinks pointing at the same URL remain navigable.
func (s *Store) ResolveRemoteImages(ctx context.Context, message *Message) error {
	if err := s.db.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM remote_image_grants WHERE message_id=?)",
		message.ID).Scan(&message.RemoteImagesAllowed); err != nil {
		return err
	}
	rows, err := s.db.QueryContext(ctx, "SELECT url,digest,media_type FROM remote_images WHERE message_id=?", message.ID)
	if err != nil {
		return err
	}
	type stored struct{ url, digest, mediaType string }
	var images []stored
	for rows.Next() {
		var image stored
		if err := rows.Scan(&image.url, &image.digest, &image.mediaType); err != nil {
			rows.Close()
			return err
		}
		images = append(images, image)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, image := range images {
		resolved, err := s.remoteImageData(message.ID, image.url, image.digest, image.mediaType)
		if err != nil {
			continue
		}
		message.RemoteImages = append(message.RemoteImages, resolved)
	}
	return nil
}

// Deletion triggers enqueue digests in the same transaction that deletes the mail.
// The queue survives a restart. Files are removed only after their final reference.
func (s *Store) collectRemoteImages(ctx context.Context) error {
	var pending bool
	if err := s.db.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM remote_image_garbage)").Scan(&pending); err != nil {
		return err
	}
	if !pending {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	rows, err := tx.QueryContext(ctx, `SELECT digest FROM remote_image_garbage
		WHERE NOT EXISTS(SELECT 1 FROM remote_images WHERE remote_images.digest=remote_image_garbage.digest)
		AND NOT EXISTS(SELECT 1 FROM attachments WHERE attachments.digest=remote_image_garbage.digest)`)
	if err != nil {
		return err
	}
	var garbage []string
	for rows.Next() {
		var digest string
		if err := rows.Scan(&digest); err != nil {
			rows.Close()
			return err
		}
		garbage = append(garbage, digest)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, digest := range garbage {
		if len(digest) != 64 || strings.Trim(digest, "0123456789abcdef") != "" {
			return ErrInvalid
		}
		if err := os.Remove(filepath.Join(s.path+".blobs", digest)); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM remote_image_garbage"); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) runRemoteImageCleanup() {
	defer close(s.remoteImagesDone)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-s.remoteImagesStop:
			return
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			_ = s.collectRemoteImages(ctx)
			cancel()
		}
	}
}

// Reading this endpoint never grants consent or downloads from a provider.
func (s *Store) RemoteImageFile(ctx context.Context, messageID, raw string) (string, *os.File, error) {
	var digest, mediaType string
	err := s.db.QueryRowContext(ctx, "SELECT digest,media_type FROM remote_images WHERE message_id=? AND url=?", messageID, raw).Scan(&digest, &mediaType)
	if err != nil {
		return "", nil, mapped(err)
	}
	if len(digest) != 64 || strings.Trim(digest, "0123456789abcdef") != "" {
		return "", nil, ErrInvalid
	}
	file, err := os.Open(filepath.Join(s.path+".blobs", digest))
	if errors.Is(err, os.ErrNotExist) {
		err = ErrNotFound
	}
	return mediaType, file, err
}
