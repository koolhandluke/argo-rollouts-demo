package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestRootHandlerReturns200WithJSON(t *testing.T) {
	os.Setenv("APP_VERSION", "v1.0.0")
	defer os.Unsetenv("APP_VERSION")

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()

	rootHandler(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", w.Code)
	}

	var resp struct {
		Version  string `json:"version"`
		Hostname string `json:"hostname"`
		Message  string `json:"message"`
	}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if resp.Message != "hello" {
		t.Errorf("expected message 'hello', got %q", resp.Message)
	}
	if resp.Hostname == "" {
		t.Errorf("expected non-empty hostname")
	}
}

func TestVersionFromEnvVar(t *testing.T) {
	os.Setenv("APP_VERSION", "v2.3.4")
	defer os.Unsetenv("APP_VERSION")

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()

	rootHandler(w, req)

	var resp struct {
		Version string `json:"version"`
	}
	json.NewDecoder(w.Body).Decode(&resp)

	if resp.Version != "v2.3.4" {
		t.Errorf("expected version 'v2.3.4', got %q", resp.Version)
	}
}

func TestVersionDefaultsToUnknown(t *testing.T) {
	os.Unsetenv("APP_VERSION")

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()

	rootHandler(w, req)

	var resp struct {
		Version string `json:"version"`
	}
	json.NewDecoder(w.Body).Decode(&resp)

	if resp.Version != "unknown" {
		t.Errorf("expected version 'unknown', got %q", resp.Version)
	}
}

func TestHealthzReturnsOK(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	w := httptest.NewRecorder()

	healthzHandler(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", w.Code)
	}
	if w.Body.String() != `{"status":"ok"}` {
		t.Errorf("unexpected body: %s", w.Body.String())
	}
}
