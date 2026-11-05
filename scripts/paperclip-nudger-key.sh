#!/usr/bin/env bash
# Mint a board API key for the paperclip-nudger CronJob, store it in
# kubernetes/apps/paperclip/nudger-token.sops.yaml, add that secret to the kustomization and
# unsuspend the CronJob. The key is never printed or passed via argv. Re-run to rotate, then
# revoke the old key (Paperclip > board API keys). Needs `npx paperclipai auth login` first.
#
# Usage: paperclip-nudger-key.sh   (EXPIRY_DAYS=90 by default)

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/kubernetes/apps/paperclip"
DOMAIN="$(sed -n 's/^  domain: //p' "$REPO_ROOT/kubernetes/settings/orion/cluster-settings.yaml")"
BASE="https://paperclip.$DOMAIN"
DAYS="${EXPIRY_DAYS:-90}"

board="$(jq -r --arg b "$BASE" '.credentials[$b].token // empty' "$HOME/.paperclip/auth.json" 2>/dev/null)"
[ -n "$board" ] || { echo "not signed in: run  npx paperclipai auth login --api-base $BASE" >&2; exit 1; }

expires="$(jq -nr --argjson d "$DAYS" 'now + ($d * 86400) | todate')"
resp="$(curl -fsS \
  --config <(printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "$board") \
  --data "$(jq -n --arg e "$expires" '{name: "paperclip-nudger", expiresAt: $e}')" \
  "$BASE/api/board-api-keys")"

umask 077
jq -j '.token' <<<"$resp" \
  | jq -Rs '{apiVersion: "v1", kind: "Secret", metadata: {name: "paperclip-nudger", namespace: "paperclip"}, type: "Opaque", stringData: {token: .}}' \
  > "$APP/nudger-token.sops.yaml"
sops --encrypt --in-place "$APP/nudger-token.sops.yaml"

yq -i '.resources |= ((. + ["nudger-token.sops.yaml"]) | unique)' "$APP/kustomization.yaml"
yq -i '.spec.suspend = false' "$APP/nudger-cronjob.yaml"
echo "key $(jq -r '.id' <<<"$resp") stored, expires $expires; CronJob unsuspended."
echo "Commit nudger-token.sops.yaml, kustomization.yaml and nudger-cronjob.yaml."
