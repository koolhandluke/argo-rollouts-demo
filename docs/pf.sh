#!/usr/bin/env bash
# pf.sh — manage Argo port-forwards (argo-rollouts-demo)
# Usage: ./docs/pf.sh start | stop | status

PID_FILE="/tmp/argo-rollouts-pf.pids"

start() {
  if [[ -f "$PID_FILE" ]]; then
    echo "Port-forwards appear to already be running. Run './docs/pf.sh stop' first."
    exit 1
  fi

  echo "Starting port-forwards..."

  kubectl port-forward svc/argocd-server -n argocd 8080:80 >/dev/null 2>&1 &
  echo $! >> "$PID_FILE"
  echo "  Argo CD        → http://localhost:8080  (admin / see password below)"

  kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100 >/dev/null 2>&1 &
  echo $! >> "$PID_FILE"
  echo "  Rollouts       → http://localhost:3100/rollouts"

  kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 >/dev/null 2>&1 &
  echo $! >> "$PID_FILE"
  echo "  Prometheus     → http://localhost:9090"

  echo ""
  echo "All started. Run './docs/pf.sh stop' to kill them all."
  echo ""
  echo "Argo CD password:"
  kubectl get secret argocd-initial-admin-secret -n argocd \
    -o jsonpath='{.data.password}' | base64 -d
  echo ""
}

stop() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "No PID file found — nothing to stop."
    exit 0
  fi

  echo "Stopping port-forwards..."
  while IFS= read -r pid; do
    if kill "$pid" 2>/dev/null; then
      echo "  Killed PID $pid"
    else
      echo "  PID $pid already gone"
    fi
  done < "$PID_FILE"
  rm -f "$PID_FILE"
  echo "Done."
}

status() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "No port-forwards running (no PID file)."
    exit 0
  fi

  echo "Port-forward status:"
  while IFS= read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "  PID $pid — running"
    else
      echo "  PID $pid — dead"
    fi
  done < "$PID_FILE"
}

case "${1:-}" in
  start)  start  ;;
  stop)   stop   ;;
  status) status ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
