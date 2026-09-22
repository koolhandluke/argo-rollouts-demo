#!/usr/bin/env bash
set -euo pipefail

VALUES_FILE="gitops-manifests/projects/demo-app/environments/dev/shared-dev-values.yaml"
WORKFLOW="Build and Push (main)"

usage() {
  echo "Usage: $0 [--dispatch] <image-tag>"
  echo "       $0 --dispatch"
  echo ""
  echo "Update dev environment to deploy the given image tag,"
  echo "commit, and push to main."
  echo ""
  echo "  --dispatch    Trigger the CI build workflow (no tag needed)."
  echo "                With a tag: update the tag AND trigger the build."
  echo ""
  echo "Examples:"
  echo "  $0 sha-c1abbd3          # set tag, commit, push"
  echo "  $0 --dispatch            # trigger CI build (builds + auto-updates dev)"
  echo "  $0 --dispatch v1.2.3     # set tag, commit, push, then trigger build"
  exit 1
}

DISPATCH=false
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dispatch) DISPATCH=true; shift ;;
    -h|--help) usage ;;
    -*) echo "Unknown flag: $1" >&2; usage ;;
    *) TAG="$1"; shift ;;
  esac
done

[[ "$DISPATCH" = false && -z "$TAG" ]] && usage

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Update tag if provided
if [[ -n "$TAG" ]]; then
  if [[ ! -f "$VALUES_FILE" ]]; then
    echo "Error: $VALUES_FILE not found" >&2
    exit 1
  fi

  sed -i '' "s|^  tag:.*|  tag: \"${TAG}\"|" "$VALUES_FILE"
  echo "Updated $VALUES_FILE → image.tag: \"$TAG\""

  git add "$VALUES_FILE"

  if git diff --cached --quiet; then
    echo "No change — tag is already \"$TAG\""
  else
    git commit -m "chore: deploy ${TAG} to dev"
    git push origin main
    echo "Pushed. Argo CD will sync demo-dev shortly."
  fi
fi

# Dispatch workflow if requested
if [[ "$DISPATCH" = true ]]; then
  echo "Triggering workflow: $WORKFLOW"
  gh workflow run "$WORKFLOW"
  echo "Workflow dispatched. Check: gh run list --workflow='${WORKFLOW}'"
fi
