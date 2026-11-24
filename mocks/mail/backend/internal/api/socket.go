package api

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

type lockedListener struct {
	*net.UnixListener
	lock *os.File
	once sync.Once
}

func (l *lockedListener) Close() error {
	err := l.UnixListener.Close()
	l.once.Do(func() { l.lock.Close() })
	return err
}

// Listen holds a lock until the listener closes and only replaces a refused socket.
func Listen(path string) (net.Listener, error) {
	if !filepath.IsAbs(path) {
		return nil, fmt.Errorf("socket path must be absolute")
	}
	if len(path) > 100 {
		return nil, fmt.Errorf("socket path is too long; choose a shorter --socket path")
	}
	dir := filepath.Dir(path)
	if e := os.MkdirAll(dir, 0700); e != nil {
		return nil, e
	}
	info, e := os.Stat(dir)
	if e != nil {
		return nil, e
	}
	if info.Mode().Perm()&0077 != 0 {
		return nil, fmt.Errorf("socket directory must be private (mode 0700)")
	}
	lock, e := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR|syscall.O_NOFOLLOW, 0600)
	if e != nil {
		return nil, e
	}
	keepLock := false
	defer func() {
		if !keepLock {
			lock.Close()
		}
	}()
	if e = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
		return nil, fmt.Errorf("mail socket is locked: %w", e)
	}
	existing, e := os.Lstat(path)
	if e == nil {
		if existing.Mode()&os.ModeSocket == 0 {
			return nil, fmt.Errorf("mail socket path is occupied by a non-socket")
		}
		conn, err := net.DialTimeout("unix", path, time.Second)
		if err == nil {
			conn.Close()
			return nil, fmt.Errorf("mail socket is already in use")
		}
		if !errors.Is(err, syscall.ECONNREFUSED) {
			return nil, fmt.Errorf("could not verify old mail socket: %w", err)
		}
		if e = os.Remove(path); e != nil {
			return nil, fmt.Errorf("could not remove inactive mail socket: %w", e)
		}
	} else if !errors.Is(e, os.ErrNotExist) {
		return nil, e
	}
	l, e := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if e != nil {
		return nil, e
	}
	if e = os.Chmod(path, 0600); e != nil {
		l.Close()
		return nil, e
	}
	keepLock = true
	return &lockedListener{UnixListener: l, lock: lock}, nil
}
