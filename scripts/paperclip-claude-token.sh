#!/usr/bin/env bash
# Put the clipboard contents into kubernetes/apps/paperclip/secret.yaml as
# CLAUDE_CODE_OAUTH_TOKEN. The value is never printed or passed via argv.
#
# Usage: paperclip-claude-token.sh   (after `claude setup-token`, copy the token)

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET="$REPO_ROOT/kubernetes/apps/paperclip/secret.yaml"

token="$(pbpaste | tr -d '[:space:]')"
case "$token" in
  sk-ant-oat*) ;;
  *) echo "clipboard does not look like a Claude OAuth token (expected sk-ant-oat...)" >&2; exit 1 ;;
esac

printf '%s' "$token" | jq -Rs . \
  | sops set --value-stdin "$SECRET" '["stringData"]["CLAUDE_CODE_OAUTH_TOKEN"]'
echo "CLAUDE_CODE_OAUTH_TOKEN set (${#token} characters) in $SECRET"
