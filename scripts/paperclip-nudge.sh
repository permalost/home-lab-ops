#!/usr/bin/env bash
# Run the reviewer nudger from this machine. Dry run unless APPLY=1.
set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN="$(sed -n 's/^  domain: //p' "$REPO_ROOT/kubernetes/settings/orion/cluster-settings.yaml")"
BASE="https://paperclip.$DOMAIN"
token="$(jq -r --arg b "$BASE" '.credentials[$b].token // empty' "$HOME/.paperclip/auth.json" 2>/dev/null)"
[ -n "$token" ] || { echo "not signed in: run  npx paperclipai auth login --api-base $BASE" >&2; exit 1; }

PAPERCLIP_URL="$BASE" PAPERCLIP_TOKEN="$token" APPLY="${APPLY:-}" \
  node "$REPO_ROOT/kubernetes/apps/paperclip/nudger.mjs"
