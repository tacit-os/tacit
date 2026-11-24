package backend

import (
	"bytes"
	"context"
	"os/exec"
)

type SystemCredentials struct{}

func (SystemCredentials) Get(ctx context.Context, id string) ([]byte, error) {
	result, err := exec.CommandContext(ctx, "secret-tool", "lookup", "application", "org.tacit.maild", "account", id).Output()
	if err != nil {
		return nil, ErrCredentialStore
	}
	return bytes.TrimSuffix(result, []byte("\n")), nil
}

func (SystemCredentials) Put(ctx context.Context, id string, value []byte) error {
	cmd := exec.CommandContext(ctx, "secret-tool", "store", "--label=Tacit Mail", "application", "org.tacit.maild", "account", id)
	cmd.Stdin = bytes.NewReader(value)
	if cmd.Run() != nil {
		return ErrCredentialStore
	}
	return nil
}

func (SystemCredentials) Delete(ctx context.Context, id string) error {
	if exec.CommandContext(ctx, "secret-tool", "clear", "application", "org.tacit.maild", "account", id).Run() != nil {
		return ErrCredentialStore
	}
	return nil
}
