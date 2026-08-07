#!/usr/bin/env bash
# Renders every Flux Kustomization for a cluster, then applies variable
# substitution from the cluster's ConfigMap (and optionally SOPS Secret).
# Mirrors Flux's postBuild.substituteFrom behaviour without a live cluster.
#
# Usage: scripts/flux-build.sh <cluster>
#   cluster: orion  (default: orion)
#
# Prerequisites: kustomize, yq, python3
#                sops (when the cluster has a cluster-secrets.sops.yaml and
#                SOPS_AGE_KEY_FILE is set)

set -euo pipefail

CLUSTER="${1:-orion}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_DIR="$REPO_ROOT/kubernetes/clusters/$CLUSTER"
# settings/ lives outside CLUSTER_DIR (kubernetes/settings/<cluster>/, not
# kubernetes/clusters/<cluster>/settings/) so Flux's implicit directory walk
# of CLUSTER_DIR never applies it without decryption.
SETTINGS_DIR="$REPO_ROOT/kubernetes/settings/$CLUSTER"

command -v kustomize >/dev/null 2>&1 || { echo "ERROR: kustomize not found. Run: task gen:tools" >&2; exit 1; }
command -v yq        >/dev/null 2>&1 || { echo "ERROR: yq not found. Run: task gen:tools" >&2; exit 1; }
command -v python3   >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }

[[ -d "$CLUSTER_DIR" ]] || { echo "ERROR: cluster directory not found: $CLUSTER_DIR" >&2; exit 1; }

# ── Variable substitution ────────────────────────────────────────────────────
# Mirrors Flux's postBuild.substituteFrom: replaces ${VAR} in rendered YAML.

SETTINGS_FILE="$SETTINGS_DIR/cluster-settings.yaml"

[[ -f "$SETTINGS_FILE" ]] || { echo "ERROR: settings file not found: $SETTINGS_FILE" >&2; exit 1; }

# Export ConfigMap data keys as env vars
while IFS='=' read -r key val; do
  [[ -z "$key" ]] && continue
  export "$key"="$val"
done < <(yq eval '.data | to_entries | .[] | .key + "=" + .value' "$SETTINGS_FILE")

# Optionally decrypt the cluster's SOPS secret and export its vars too.
SECRETS_FILE="$SETTINGS_DIR/cluster-secrets.sops.yaml"
if [[ -f "$SECRETS_FILE" ]]; then
  if [[ -n "${SOPS_AGE_KEY_FILE:-}" && -f "${SOPS_AGE_KEY_FILE:-}" ]]; then
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

  # name|path|substitute per Kustomization object (files may hold multiple
  # documents). substitute = spec.postBuild.substitute literals, separate
  # from the ConfigMap/Secret substituteFrom handled above.
  while IFS='|' read -r name path substitute; do
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

    # scoped to this Kustomization only; unset after building
    LITERAL_KEYS=()
    if [[ -n "$substitute" ]]; then
      IFS=';' read -ra pairs <<< "$substitute"
      for pair in "${pairs[@]}"; do
        [[ -z "$pair" ]] && continue
        key="${pair%%=*}"
        val="${pair#*=}"
        export "$key"="$val"
        LITERAL_KEYS+=("$key")
      done
    fi

    if RENDERED="$(kustomize build "$BUILD_PATH" "${KUSTOMIZE_FLAGS[@]}" | python3 -c "$ENVSUBST_PY")"; then
      # a successful build doesn't mean substitution succeeded — check for leftovers
      UNRESOLVED="$(printf '%s' "$RENDERED" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*(:[^}]*)?\}' | sort -u || true)"
      if [[ -n "$UNRESOLVED" ]]; then
        echo "  ✗ $name — unresolved variable(s):"
        echo "$UNRESOLVED" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
      else
        echo "  ✓ $name"
      fi
    else
      echo "  ✗ $name — FAILED (re-running to show error):"
      kustomize build "$BUILD_PATH" "${KUSTOMIZE_FLAGS[@]}" \
        | python3 -c "$ENVSUBST_PY" \
        >&2 || true
      FAILED=$((FAILED + 1))
    fi

    for k in "${LITERAL_KEYS[@]:-}"; do
      [[ -n "$k" ]] && unset "$k"
    done

  done < <(yq eval \
    'select(.kind == "Kustomization" and (.apiVersion | test("kustomize.toolkit.fluxcd.io"))) | .metadata.name + "|" + .spec.path + "|" + ((.spec.postBuild.substitute // {}) | to_entries | map(.key + "=" + .value) | join(";"))' \
    "$ks_file" 2>/dev/null)

done

echo ""
echo "────────────────────────────────────────"
printf   "Results: %d/%d passed" "$((TOTAL - FAILED))" "$TOTAL"
[[ $FAILED -eq 0 ]] && echo "  ✓" || echo "  ✗ ($FAILED failed)"
echo "────────────────────────────────────────"
[[ $FAILED -eq 0 ]]
