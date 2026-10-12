#!/usr/bin/env bash
# Configure the live Forgejo over its API (org, bot users, scoped tokens,
# branch protection). Admin credentials come from the sops secret; nothing
# secret is printed or left on disk unencrypted.
#
# Usage:
#   forgejo.sh bootstrap            # org + team + bot users (idempotent)
#   forgejo.sh tokens [OUT=<path>]  # (re)mint bot tokens into a sops secret
#   forgejo.sh protect REPO=<name> TIER=auto|human
#   forgejo.sh runner-token         # org runner registration token -> sops secret

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET="$REPO_ROOT/kubernetes/apps/forgejo/secret.yaml"
DOMAIN="$(sed -n 's/^  domain: //p' "$REPO_ROOT/kubernetes/settings/orion/cluster-settings.yaml")"
BASE="${FORGEJO_URL:-https://git.$DOMAIN}/api/v1"
ORG="wdo"
ADMIN="$(sops -d --extract '["stringData"]["username"]' "$SECRET")"
ADMIN_PW="$(sops -d --extract '["stringData"]["password"]' "$SECRET")"

# bot -> token scopes
BOTS="agent-dev agent-review agent-docs agent-chief"
scopes() {
  case "$1" in
    agent-chief) echo "read:repository,write:issue,read:organization,read:user" ;;
    *)           echo "write:repository,write:issue,read:organization,read:user" ;;
  esac
}

# api <user> <password> <method> <path> [json]; prints body, fails on HTTP >= 400
api() {
  local user="$1" pw="$2" method="$3" path="$4" body="${5:-}" out code
  out="$(mktemp)"
  code="$(curl -sS -o "$out" -w '%{http_code}' -u "$user:$pw" -X "$method" \
    -H 'Content-Type: application/json' ${body:+-d "$body"} "$BASE$path")"
  cat "$out"; rm -f "$out"
  [ "$code" -lt 400 ] || { echo "HTTP $code on $method $path" >&2; return 1; }
}
admin() { api "$ADMIN" "$ADMIN_PW" "$@"; }
exists() { [ "$(curl -s -o /dev/null -w '%{http_code}' -u "$ADMIN:$ADMIN_PW" "$BASE$1")" = 200 ]; }
rand() { openssl rand -base64 33 | tr -d '/+=' | cut -c1-32; }

bootstrap() {
  exists "/orgs/$ORG" || admin POST /orgs "{\"username\":\"$ORG\",\"visibility\":\"private\"}" >/dev/null
  echo "org $ORG ok"

  local team_id
  team_id="$(admin GET "/orgs/$ORG/teams/search?q=agents" | jq -r '.data[]? | select(.name=="agents") | .id')"
  if [ -z "$team_id" ]; then
    team_id="$(admin POST "/orgs/$ORG/teams" '{"name":"agents","permission":"write","includes_all_repositories":true,"can_create_org_repo":false,"units":["repo.code","repo.issues","repo.pulls","repo.releases","repo.packages"]}' | jq -r .id)"
  fi
  echo "team agents ok"

  for bot in $BOTS; do
    exists "/users/$bot" || admin POST /admin/users \
      "{\"username\":\"$bot\",\"email\":\"$bot@noreply.$DOMAIN\",\"password\":\"$(rand)\",\"must_change_password\":false,\"visibility\":\"private\"}" >/dev/null
    admin PUT "/teams/$team_id/members/$bot" >/dev/null
    echo "user $bot ok"
  done
}

tokens() {
  local out="${OUT:-$REPO_ROOT/kubernetes/apps/paperclip/forgejo-tokens.sops.yaml}" tmp bot pw tok
  tmp="$(mktemp)"
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: forgejo-bot-tokens\ntype: Opaque\nstringData:\n' > "$tmp"
  for bot in $BOTS; do
    # Fresh throwaway password per run: token creation needs the bot's own basic auth.
    pw="$(rand)"
    admin PATCH "/admin/users/$bot" "{\"login_name\":\"$bot\",\"source_id\":0,\"password\":\"$pw\",\"must_change_password\":false}" >/dev/null
    api "$bot" "$pw" DELETE "/users/$bot/tokens/paperclip" >/dev/null 2>&1 || true
    tok="$(api "$bot" "$pw" POST "/users/$bot/tokens" \
      "{\"name\":\"paperclip\",\"scopes\":[\"$(scopes "$bot" | sed 's/,/","/g')\"]}" | jq -r .sha1)"
    printf '  %s: %s\n' "$(echo "$bot" | tr a-z- A-Z_)_TOKEN" "$tok" >> "$tmp"
    admin PATCH "/admin/users/$bot" "{\"login_name\":\"$bot\",\"source_id\":0,\"password\":\"$(rand)\",\"must_change_password\":false}" >/dev/null
    echo "token $bot minted"
  done
  mkdir -p "$(dirname "$out")"
  sops --encrypt --filename-override "$out" --input-type yaml --output-type yaml "$tmp" > "$out"
  rm -f "$tmp"
  echo "wrote $out (sops-encrypted)"
}

runner_token() {
  local out="$REPO_ROOT/kubernetes/apps/forgejo-runner/secret.yaml" tmp tok
  tok="$(admin GET "/orgs/$ORG/actions/runners/registration-token" | jq -r .token)"
  tmp="$(mktemp)"
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: runner-registration\ntype: Opaque\nstringData:\n  token: %s\n' "$tok" > "$tmp"
  sops --encrypt --filename-override "$out" --input-type yaml --output-type yaml "$tmp" > "$out"
  rm -f "$tmp"
  echo "wrote $out (sops-encrypted)"
}

# tier/auto: agent-review approval merges; tier/human: only the admin approves and merges.
protect() {
  local repo="$1" tier="$2" body
  case "$tier" in
    auto)  body='{"approvals_whitelist_username":["agent-review"],"merge_whitelist_usernames":["'"$ADMIN"'","agent-chief"]}' ;;
    human) body='{"approvals_whitelist_username":["'"$ADMIN"'"],"merge_whitelist_usernames":["'"$ADMIN"'"]}' ;;
    *) echo "TIER must be auto or human" >&2; exit 1 ;;
  esac
  body="$(jq -c '. + {rule_name:"main",enable_push:false,enable_approvals_whitelist:true,required_approvals:1,enable_merge_whitelist:true,block_on_rejected_reviews:true,dismiss_stale_approvals:true}' <<<"$body")"
  admin DELETE "/repos/$ORG/$repo/branch_protections/main" >/dev/null 2>&1 || true
  admin POST "/repos/$ORG/$repo/branch_protections" "$body" >/dev/null
  echo "$ORG/$repo main protected (tier/$tier)"
}

cmd="${1:-}"; shift || true
REPO=""; TIER=""; OUT=""
for arg in "$@"; do
  case "$arg" in
    REPO=*) REPO="${arg#REPO=}" ;;
    TIER=*) TIER="${arg#TIER=}" ;;
    OUT=*)  OUT="${arg#OUT=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done
case "$cmd" in
  bootstrap) bootstrap ;;
  tokens)    tokens ;;
  runner-token) runner_token ;;
  protect)   protect "${REPO:?REPO required}" "${TIER:?TIER required}" ;;
  *) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 1 ;;
esac
