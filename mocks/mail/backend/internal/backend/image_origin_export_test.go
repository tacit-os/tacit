package backend

import "net/http"

// Test-only hook for exercising the HTTP API with a deterministic image origin.
func SetImageOriginClientForTest(store *Store, client *http.Client) {
	store.remoteImagesHTTP = client
}
