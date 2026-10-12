#!/usr/bin/env bash
# Hire a Paperclip agent through the API (the "New agent" form can't express a local
# OpenCode model or a custom env). Needs `npx paperclipai auth login` first.
# Uses /agent-hires, so with "require board approval" on, the hire waits for you in
# Paperclip > Approvals. Tokens come from sops and are never printed or put in argv.
#
# Usage:
#   paperclip-agent.sh create NAME=<name> ROLE=<role> ADAPTER=<adapter> BOT=<agent-...> \
#       PLAYBOOK_FILE=<agents/x.md> [MODEL=<provider/model>] [TITLE=..] [REPORTS_TO=<agent name>] \
#       [BUDGET_CENTS=0] [ROTATE=1] [DRY_RUN=1]
#
# Example:
#   paperclip-agent.sh create NAME=Dev ROLE=engineer ADAPTER=opencode_local \
#       MODEL=spark/GLM-5.3-Flash-EXL3 BOT=agent-dev PLAYBOOK_FILE=agents/developer.md REPORTS_TO=Spiff

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN="$(sed -n 's/^  domain: //p' "$REPO_ROOT/kubernetes/settings/orion/cluster-settings.yaml")"
BASE="${PAPERCLIP_URL:-https://paperclip.$DOMAIN}"
FORGEJO_URL="https://git.$DOMAIN"
PLAYBOOK_DIR="${PLAYBOOK_DIR:-$HOME/code/agent-playbook}"
TOKENS_FILE="$REPO_ROOT/kubernetes/apps/paperclip/forgejo-tokens.sops.yaml"

NAME=""; ROLE=""; ADAPTER=""; MODEL=""; BOT=""; PLAYBOOK_FILE=""; TITLE=""; REPORTS_TO=""
BUDGET_CENTS="0"; ROTATE=""; DRY_RUN=""
cmd="${1:-}"; shift || true
for arg in "$@"; do
  case "$arg" in
    NAME=*) NAME="${arg#NAME=}" ;;
    ROLE=*) ROLE="${arg#ROLE=}" ;;
    ADAPTER=*) ADAPTER="${arg#ADAPTER=}" ;;
    MODEL=*) MODEL="${arg#MODEL=}" ;;
    BOT=*) BOT="${arg#BOT=}" ;;
    PLAYBOOK_FILE=*) PLAYBOOK_FILE="${arg#PLAYBOOK_FILE=}" ;;
    TITLE=*) TITLE="${arg#TITLE=}" ;;
    REPORTS_TO=*) REPORTS_TO="${arg#REPORTS_TO=}" ;;
    BUDGET_CENTS=*) BUDGET_CENTS="${arg#BUDGET_CENTS=}" ;;
    ROTATE=*) ROTATE="${arg#ROTATE=}" ;;
    DRY_RUN=*) DRY_RUN="${arg#DRY_RUN=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done
[ "$cmd" = create ] || { sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 1; }
: "${NAME:?NAME required}" "${ROLE:?ROLE required}" "${ADAPTER:?ADAPTER required}" "${BOT:?BOT required}" "${PLAYBOOK_FILE:?PLAYBOOK_FILE required}"

BOARD_TOKEN="$(jq -r --arg b "$BASE" '.credentials[$b].token // empty' "$HOME/.paperclip/auth.json" 2>/dev/null)"
[ -n "$BOARD_TOKEN" ] || { echo "not signed in: run  npx paperclipai auth login --api-base $BASE" >&2; exit 1; }

# api <method> <path> [json on stdin]; the bearer token goes through a config fd, not argv.
api() {
  local method="$1" path="$2" out code
  out="$(mktemp)"
  code="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" -H 'Content-Type: application/json' \
    --config <(printf 'header = "Authorization: Bearer %s"\n' "$BOARD_TOKEN") \
    ${3:+--data-binary @-} "$BASE$path")"
  cat "$out"; rm -f "$out"
  [ "$code" -lt 400 ] || { echo "HTTP $code on $method $path" >&2; return 1; }
}

COMPANY_ID="${COMPANY_ID:-$(api GET '/api/companies' | jq -r '.[0].id')}"
[ -n "$COMPANY_ID" ] && [ "$COMPANY_ID" != null ] || { echo "no company found" >&2; exit 1; }

agents="$(api GET "/api/companies/$COMPANY_ID/agents")"
if jq -e --arg n "$NAME" 'map(select(.name | ascii_downcase == ($n | ascii_downcase) and .status != "terminated")) | length > 0' <<<"$agents" >/dev/null; then
  echo "an agent named $NAME already exists; refusing to create another" >&2; exit 1
fi
reports_to_id="null"
if [ -n "$REPORTS_TO" ]; then
  reports_to_id="$(jq -r --arg n "$REPORTS_TO" 'map(select(.name | ascii_downcase == ($n | ascii_downcase)))[0].id // empty' <<<"$agents")"
  [ -n "$reports_to_id" ] || { echo "no agent named $REPORTS_TO; have: $(jq -r 'map(.name)|join(", ")' <<<"$agents")" >&2; exit 1; }
  reports_to_id="\"$reports_to_id\""
fi

# Forgejo token -> Paperclip secret (reuse by name unless ROTATE=1).
secret_name="forgejo-token-$BOT"
secret_id="$(api GET "/api/companies/$COMPANY_ID/secrets" | jq -r --arg n "$secret_name" '(if type == "array" then . else (.secrets // []) end)[] | select(.name==$n) | .id' | head -1)"
tok_key="$(echo "$BOT" | tr a-z- A-Z_)_TOKEN"
if [ -n "$DRY_RUN" ]; then
  [ -n "$secret_id" ] && echo "(dry run) secret $secret_name exists: $secret_id" || { echo "(dry run) would create secret $secret_name"; secret_id="<new-secret-id>"; }
else
  if [ -z "$secret_id" ]; then
    secret_id="$(TOK="$(sops -d --extract "[\"stringData\"][\"$tok_key\"]" "$TOKENS_FILE")" \
      jq -n --arg n "$secret_name" '{name:$n, value:env.TOK}' \
      | api POST "/api/companies/$COMPANY_ID/secrets" - | jq -r .id)"
    echo "created secret $secret_name"
  elif [ -n "$ROTATE" ]; then
    TOK="$(sops -d --extract "[\"stringData\"][\"$tok_key\"]" "$TOKENS_FILE")" \
      jq -n '{value:env.TOK}' | api POST "/api/secrets/$secret_id/rotate" - >/dev/null
    echo "rotated secret $secret_name"
  fi
fi

agents_md="$PLAYBOOK_DIR/$PLAYBOOK_FILE"; rules_md="$PLAYBOOK_DIR/rules.md"
[ -f "$agents_md" ] && [ -f "$rules_md" ] || { echo "missing $agents_md or $rules_md (set PLAYBOOK_DIR)" >&2; exit 1; }

body="$(jq -n \
  --arg name "$NAME" --arg role "$ROLE" --arg title "${TITLE:-$NAME}" --arg adapter "$ADAPTER" \
  --arg model "$MODEL" --arg furl "$FORGEJO_URL" --arg sid "$secret_id" --argjson budget "$BUDGET_CENTS" \
  --argjson reports "$reports_to_id" --rawfile agents "$agents_md" --rawfile rules "$rules_md" '
  {
    name: $name, role: $role, title: $title, reportsTo: $reports, adapterType: $adapter,
    adapterConfig: (
      (if $model == "" then {} else {model: $model} end) +
      {env: {
        FORGEJO_URL: {type: "plain", value: $furl},
        FORGEJO_TOKEN: {type: "secret_ref", secretId: $sid, version: "latest"}
      }}),
    instructionsBundle: {entryFile: "AGENTS.md", files: {"AGENTS.md": $agents, "rules.md": $rules}},
    budgetMonthlyCents: $budget
  }')"

if [ -n "$DRY_RUN" ]; then
  echo "(dry run) POST $BASE/api/companies/$COMPANY_ID/agent-hires"
  jq '.instructionsBundle.files |= map_values("<\(length) chars>")' <<<"$body"
  exit 0
fi
resp="$(printf '%s' "$body" | api POST "/api/companies/$COMPANY_ID/agent-hires" -)"
jq -r '"agent \(.agent.name) (\(.agent.id)) status=\(.agent.status)" + (if .approval then "  approval=\(.approval.id)" else "" end)' <<<"$resp"
[ "$(jq -r .agent.status <<<"$resp")" != pending_approval ] || echo "waiting for you: Paperclip > Approvals"
