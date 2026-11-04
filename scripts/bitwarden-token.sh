#!/usr/bin/env bash
# Put a Bitwarden Secrets Manager machine-account access token into its sops
# token Secret. The value is never printed or passed via argv.
#
# Usage: bitwarden-token.sh ACCOUNT=<eso-orion|eso-paperclip>
#        (copy the token to the clipboard, or pipe it on stdin)

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# sops finds the repo .sops.yaml from the working directory, so stay at the root.
cd "$REPO_ROOT"
STORES_DIR="kubernetes/infrastructure/external-secrets/stores"

case "${1:-}" in
  ACCOUNT=*) account="${1#ACCOUNT=}" ;;
  *) echo "usage: bitwarden-token.sh ACCOUNT=<eso-orion|eso-paperclip>" >&2; exit 1 ;;
esac

case "$account" in
  eso-orion) secret_name="bitwarden-orion-token"; file="eso-orion.sops.yaml" ;;
  eso-paperclip) secret_name="bitwarden-paperclip-token"; file="eso-paperclip.sops.yaml" ;;
  *) echo "unknown account '$account' (expected eso-orion or eso-paperclip)" >&2; exit 1 ;;
esac

command -v sops >/dev/null || { echo "sops not found" >&2; exit 1; }
command -v yq >/dev/null || { echo "yq not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

if [ -t 0 ]; then
  command -v pbpaste >/dev/null || { echo "no clipboard: pipe the token on stdin instead" >&2; exit 1; }
  token="$(pbpaste | tr -d '[:space:]')"
else
  token="$(cat | tr -d '[:space:]')"
fi

case "$token" in
  [0-9].*.*) ;;
  *) echo "input does not look like a Bitwarden access token (expected 0.<uuid>.<secret>)" >&2; exit 1 ;;
esac

target="$STORES_DIR/$file"
kustomization="$STORES_DIR/kustomization.yaml"

# sops set --value-stdin expects a JSON-encoded value.
token_json="$(printf '%s' "$token" | jq -Rs .)"

if [ -f "$target" ]; then
  # Rotation: the file already exists and decrypts with the repo age key.
  printf '%s' "$token_json" | sops set --value-stdin "$target" '["stringData"]["token"]'
else
  # First run: create the Secret. The temporary file is named *.sops.yaml so
  # the repo .sops.yaml creation rules apply, and is encrypted in place —
  # the plaintext never touches a path git tracks.
  tmp="$STORES_DIR/.tmp-$file"
  trap 'rm -f "$tmp"' EXIT
  cat > "$tmp" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: external-secrets
type: Opaque
stringData:
  token: ${token_json}
EOF
  sops encrypt --in-place "$tmp"
  mv "$tmp" "$target"
  if [ -z "$(yq '.resources // [] | .[] | select(. == "'"$file"'")' "$kustomization")" ]; then
    yq -i '.resources += ["'"$file"'"]' "$kustomization"
  fi
fi

echo "$secret_name set (${#token} characters) in $target"
