#!/usr/bin/env bash
# Renders every Flux Kustomization for a cluster, then applies variable
# substitution from the cluster's ConfigMap (and optionally SOPS Secret).
# Mirrors Flux's postBuild.substituteFrom behaviour without a live cluster.
#
# Usage: scripts/flux-build.sh <cluster>
#   cluster: orion | na  (default: orion)
#
# Prerequisites: kustomize, yq, python3
#                sops (only for na when SOPS_AGE_KEY_FILE is set)

set -euo pipefail

CLUSTER="${1:-orion}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_DIR="$REPO_ROOT/kubernetes/clusters/$CLUSTER"

command -v kustomize >/dev/null 2>&1 || { echo "ERROR: kustomize not found. Run: task gen:tools" >&2; exit 1; }
command -v yq        >/dev/null 2>&1 || { echo "ERROR: yq not found. Run: task gen:tools" >&2; exit 1; }
command -v python3   >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }

[[ -d "$CLUSTER_DIR" ]] || { echo "ERROR: cluster directory not found: $CLUSTER_DIR" >&2; exit 1; }

# ── Variable substitution ────────────────────────────────────────────────────
# Mirrors Flux's postBuild.substituteFrom: replaces ${VAR} in rendered YAML.

case "$CLUSTER" in
  na)   SETTINGS_FILE="$CLUSTER_DIR/settings/cluster-settings.yaml" ;;
  *)    SETTINGS_FILE="$CLUSTER_DIR/cluster-settings.yaml" ;;
esac

[[ -f "$SETTINGS_FILE" ]] || { echo "ERROR: settings file not found: $SETTINGS_FILE" >&2; exit 1; }

# Export ConfigMap data keys as env vars
while IFS='=' read -r key val; do
  [[ -z "$key" ]] && continue
  export "$key"="$val"
done < <(yq eval '.data | to_entries | .[] | .key + "=" + .value' "$SETTINGS_FILE")

# For na: optionally decrypt SOPS secret and export its vars too
if [[ "$CLUSTER" == "na" ]]; then
  SECRETS_FILE="$CLUSTER_DIR/settings/cluster-secrets.sops.yaml"
  if [[ -f "$SECRETS_FILE" && -n "${SOPS_AGE_KEY_FILE:-}" && -f "${SOPS_AGE_KEY_FILE:-}" ]]; then
    echo "INFO  Decrypting cluster secrets for $CLUSTER"
    DECRYPTED="$(sops -d "$SECRETS_FILE")"

    # stringData: plain text values
    while IFS='=' read -r key val; do
      [[ -z "$key" ]] && continue
      export "$key"="$val"
    done < <(echo "$DECRYPTED" | yq eval '.stringData // {} | to_entries | .[] | .key + "=" + .value' -)

    # data: base64-encoded values — decode before exporting
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      key="${entry%%=*}"
      b64="${entry#*=}"
      decoded="$(printf '%s' "$b64" | base64 -d 2>/dev/null || printf '%s' "$b64")"
      export "$key"="$decoded"
    done < <(echo "$DECRYPTED" | yq eval '.data // {} | to_entries | .[] | .key + "=" + .value' -)
  else
    echo "WARN  SOPS_AGE_KEY_FILE not set — secret substitution vars skipped for $CLUSTER"
  fi
fi

# Python-based ${VAR} substitution (cross-platform, no envsubst dependency).
# Matches ${VAR} and ${VAR:=default} — resolves from env, keeps original if missing.
ENVSUBST_PY='
import sys, re, os
content = sys.stdin.read()
def sub(m):
    return os.environ.get(m.group(1), m.group(0))
sys.stdout.write(re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::[^}]*)?\}", sub, content))
'

# ── Build each Flux Kustomization ────────────────────────────────────────────

FAILED=0
TOTAL=0
KUSTOMIZE_FLAGS=("--load-restrictor=LoadRestrictionsNone")

for ks_file in $(find "$CLUSTER_DIR" -maxdepth 3 -name '*.yaml' \
    -not -path '*/flux-system/*' | sort); do

  # Extract name|path for every Flux Kustomization object in this file.
  # Files can contain multiple YAML documents (e.g. cert-manager + cert-manager-issuers).
  while IFS='|' read -r name path; do
    [[ -z "$name" || "$name" == "null" ]] && continue
    [[ -z "$path" || "$path" == "null" ]] && continue
    path="${path#./}"   # strip leading ./

    TOTAL=$((TOTAL + 1))
    printf 'BUILD  %-40s → %s\n' "$name" "$path"

    BUILD_PATH="$REPO_ROOT/$path"
    [[ -d "$BUILD_PATH" ]] || {
      echo "  ✗ $name — path not found: $BUILD_PATH"
      FAILED=$((FAILED + 1))
      continue
    }

    if kustomize build "$BUILD_PATH" "${KUSTOMIZE_FLAGS[@]}" \
        | python3 -c "$ENVSUBST_PY" \
        > /dev/null 2>&1; then
      echo "  ✓ $name"
    else
      echo "  ✗ $name — FAILED (re-running to show error):"
      kustomize build "$BUILD_PATH" "${KUSTOMIZE_FLAGS[@]}" \
        | python3 -c "$ENVSUBST_PY" \
        >&2 || true
      FAILED=$((FAILED + 1))
    fi

  done < <(yq eval \
    'select(.kind == "Kustomization" and (.apiVersion | test("kustomize.toolkit.fluxcd.io"))) | .metadata.name + "|" + .spec.path' \
    "$ks_file" 2>/dev/null)

done

echo ""
echo "────────────────────────────────────────"
printf   "Results: %d/%d passed" "$((TOTAL - FAILED))" "$TOTAL"
[[ $FAILED -eq 0 ]] && echo "  ✓" || echo "  ✗ ($FAILED failed)"
echo "────────────────────────────────────────"
[[ $FAILED -eq 0 ]]
