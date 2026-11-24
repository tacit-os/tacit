//go:build (!darwin && !linux) || (darwin && !cgo)

package backend

import "context"

type SystemCredentials struct{}

func (SystemCredentials) Get(context.Context, string) ([]byte, error) { return nil, ErrCredentialStore }
func (SystemCredentials) Put(context.Context, string, []byte) error   { return ErrCredentialStore }
func (SystemCredentials) Delete(context.Context, string) error        { return ErrCredentialStore }
