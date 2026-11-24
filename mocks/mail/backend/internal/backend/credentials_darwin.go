package backend

/*
#cgo LDFLAGS: -framework Security -framework CoreFoundation
#include <Security/Security.h>
#include <stdlib.h>

static const char service[] = "org.tacit.maild";

static OSStatus readCredential(const char *id, UInt32 len, UInt32 *size, void **value) {
	return SecKeychainFindGenericPassword(NULL, sizeof(service)-1, service, len, id, size, value, NULL);
}

static OSStatus addCredential(const char *id, UInt32 len, const void *value, UInt32 size) {
	OSStatus result = SecKeychainAddGenericPassword(NULL, sizeof(service)-1, service, len, id, size, value, NULL);
	if (result != errSecDuplicateItem) return result;
	SecKeychainItemRef item = NULL;
	result = SecKeychainFindGenericPassword(NULL, sizeof(service)-1, service, len, id, NULL, NULL, &item);
	if (result != errSecSuccess) return result;
	result = SecKeychainItemModifyAttributesAndData(item, NULL, size, value);
	CFRelease(item);
	return result;
}

static OSStatus deleteCredential(const char *id, UInt32 len) {
	SecKeychainItemRef item = NULL;
	OSStatus result = SecKeychainFindGenericPassword(NULL, sizeof(service)-1, service, len, id, NULL, NULL, &item);
	if (result == errSecItemNotFound) return errSecSuccess;
	if (result != errSecSuccess) return result;
	result = SecKeychainItemDelete(item);
	CFRelease(item);
	return result;
}
*/
import "C"

import (
	"context"
	"unsafe"
)

type SystemCredentials struct{}

func (SystemCredentials) Get(ctx context.Context, id string) ([]byte, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	key := C.CString(id)
	defer C.free(unsafe.Pointer(key))
	var size C.UInt32
	var value unsafe.Pointer
	if C.readCredential(key, C.UInt32(len(id)), &size, &value) != C.errSecSuccess {
		return nil, ErrCredentialStore
	}
	defer C.SecKeychainItemFreeContent(nil, value)
	return C.GoBytes(value, C.int(size)), nil
}

func (SystemCredentials) Put(ctx context.Context, id string, value []byte) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	key := C.CString(id)
	defer C.free(unsafe.Pointer(key))
	if len(value) == 0 || C.addCredential(key, C.UInt32(len(id)), unsafe.Pointer(&value[0]), C.UInt32(len(value))) != C.errSecSuccess {
		return ErrCredentialStore
	}
	return nil
}

func (SystemCredentials) Delete(ctx context.Context, id string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	key := C.CString(id)
	defer C.free(unsafe.Pointer(key))
	if C.deleteCredential(key, C.UInt32(len(id))) != C.errSecSuccess {
		return ErrCredentialStore
	}
	return nil
}
