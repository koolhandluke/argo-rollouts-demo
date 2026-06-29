package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var httpRequests = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total HTTP requests by status class.",
	},
	[]string{"status"},
)

func init() {
	prometheus.MustRegister(httpRequests)
}

type rootResponse struct {
	Version  string `json:"version"`
	Hostname string `json:"hostname"`
	Message  string `json:"message"`
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "unknown"
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(rootResponse{
		Version:  version,
		Hostname: hostname,
		Message:  "hello",
	})
	httpRequests.WithLabelValues("2xx").Inc()
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprint(w, `{"status":"ok"}`)
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", rootHandler)
	mux.HandleFunc("/healthz", healthzHandler)
	mux.Handle("/metrics", promhttp.Handler())

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	http.ListenAndServe(":"+port, mux)
}
