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
#   forgejo.sh migrate PROJECT=<dir under ~/code> [TIER=auto|human] [DRY_RUN=1]

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

# Copy ~/code/<project> through a deny-list, secret-scan it, push it to wdo/<project>,
# then protect main. Refuses to touch a repo that already exists.
migrate() {
  local project="$1" tier="$2" src="${SRC:-$HOME/code/$1}" stage askpass size
  [ -d "$src" ] || { echo "no such directory: $src" >&2; exit 1; }
  stage="$(mktemp -d)"; askpass="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -rf '$stage' '$askpass'" EXIT
  rsync -a --filter=':- .gitignore' \
    --exclude='.git/' --exclude='.env*' --exclude='secrets/' --exclude='*.pem' --exclude='*.key' \
    --exclude='*.crt' --exclude='auth.json' --exclude='*.sops.*' --exclude='.venv/' --exclude='venv/' \
    --exclude='env/' --exclude='node_modules/' --exclude='__pycache__/' --exclude='.claude/' \
    --exclude='reports/' --exclude='data/' --exclude='*.log' --exclude='.DS_Store' "$src/" "$stage/"
  size="$(du -sk "$stage" | cut -f1)"
  [ "$size" -lt 51200 ] || { echo "staged copy is ${size}K (>50M); aborting" >&2; exit 1; }
  echo "files to push ($size K):"; (cd "$stage" && find . -type f | sort | sed 's/^/  /')
  docker run --rm -v "$stage:/repo:ro" ghcr.io/gitleaks/gitleaks:v8.28.0 dir /repo --no-banner --redact \
    || { echo "gitleaks found secrets; nothing pushed" >&2; exit 1; }
  if [ "${DRY_RUN:-}" = 1 ]; then echo "dry run: nothing pushed"; return; fi
  ! exists "/repos/$ORG/$project" || { echo "$ORG/$project already exists; use the PR flow" >&2; exit 1; }

  admin POST "/orgs/$ORG/repos" "{\"name\":\"$project\",\"private\":true,\"default_branch\":\"main\"}" >/dev/null
  printf '#!/bin/sh\ncase "$1" in Username*) echo "$FORGEJO_GIT_USER";; *) echo "$FORGEJO_GIT_PW";; esac\n' > "$askpass"
  chmod +x "$askpass"
  git -C "$stage" init -q -b main
  git -C "$stage" add -A
  git -C "$stage" commit -q -m "Import $project from local"
  git -C "$stage" remote add origin "${BASE%/api/v1}/$ORG/$project.git"
  FORGEJO_GIT_USER="$ADMIN" FORGEJO_GIT_PW="$ADMIN_PW" GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 \
    git -C "$stage" push -q -u origin main
  echo "pushed $ORG/$project"
  protect "$project" "$tier"
}

cmd="${1:-}"; shift || true
REPO=""; TIER=""; OUT=""; PROJECT=""; SRC=""; DRY_RUN=""
for arg in "$@"; do
  case "$arg" in
    REPO=*) REPO="${arg#REPO=}" ;;
    TIER=*) TIER="${arg#TIER=}" ;;
    OUT=*)  OUT="${arg#OUT=}" ;;
    PROJECT=*) PROJECT="${arg#PROJECT=}" ;;
    SRC=*)  SRC="${arg#SRC=}" ;;
    DRY_RUN=*) DRY_RUN="${arg#DRY_RUN=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done
case "$cmd" in
  bootstrap) bootstrap ;;
  tokens)    tokens ;;
  runner-token) runner_token ;;
  migrate)   migrate "${PROJECT:?PROJECT required}" "${TIER:-auto}" ;;
  protect)   protect "${REPO:?REPO required}" "${TIER:?TIER required}" ;;
  *) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 1 ;;
esac
