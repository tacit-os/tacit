package api

import (
	"net"
	"os"
	"path/filepath"
	"testing"
)

func TestListenRecoversAbandonedSocket(t *testing.T) {
	dir, err := os.MkdirTemp("/tmp", "tacit-stale-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(dir)
	path := filepath.Join(dir, "mail.sock")
	old, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	old.SetUnlinkOnClose(false)
	if err := old.Close(); err != nil {
		t.Fatal(err)
	}
	listener, err := Listen(path)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	conn, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
}

func TestListenLeavesNonSocketUntouched(t *testing.T) {
	dir, err := os.MkdirTemp("/tmp", "tacit-file-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(dir)
	path := filepath.Join(dir, "mail.sock")
	if err := os.WriteFile(path, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if listener, err := Listen(path); err == nil {
		listener.Close()
		t.Fatal("listener replaced a regular file")
	}
	value, err := os.ReadFile(path)
	if err != nil || string(value) != "keep" {
		t.Fatalf("existing file changed: %q, %v", value, err)
	}
}
