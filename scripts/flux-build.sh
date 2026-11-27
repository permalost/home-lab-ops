#!/usr/bin/env bash
# Renders every Flux Kustomization for a cluster, then applies variable
# substitution from the cluster's ConfigMap (and optionally SOPS Secret).
# Mirrors Flux's postBuild.substituteFrom behaviour without a live cluster.
#
# Usage: scripts/flux-build.sh <cluster>
#   cluster: orion  (default: orion)
#
# Prerequisites: kustomize, yq, python3
#                sops (when the cluster has *.sops.yaml settings files and
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

# Decrypt the cluster's SOPS files and export their vars too. Without the age
# key (CI, fresh clones) the values are unknowable — substitute a placeholder
# for each name in the cluster's secret-vars.txt (names only, not values) so
# structure checks still pass. A var that is neither decrypted nor listed stays
# unresolved and fails the build below.
SECRET_VARS_FILE="$SETTINGS_DIR/secret-vars.txt"
shopt -s nullglob
for SECRETS_FILE in "$SETTINGS_DIR"/*.sops.yaml; do
  if [[ -n "${SOPS_AGE_KEY_FILE:-}" && -f "${SOPS_AGE_KEY_FILE:-}" ]]; then
    echo "INFO  Decrypting $(basename "$SECRETS_FILE") for $CLUSTER"
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
  elif [[ -f "$SECRET_VARS_FILE" ]]; then
    echo "WARN  SOPS_AGE_KEY_FILE not set — placeholder values used for $(basename "$SECRETS_FILE") vars"
    while IFS= read -r key; do
      key="${key%%#*}"; key="${key//[[:space:]]/}"
      [[ -z "$key" ]] && continue
      export "$key=__SOPS_UNAVAILABLE__"
    done < "$SECRET_VARS_FILE"
  else
    echo "WARN  SOPS_AGE_KEY_FILE not set — secret substitution vars skipped for $CLUSTER"
  fi
done
shopt -u nullglob

# Flux skips substitution on resources annotated/labelled
# kustomize.toolkit.fluxcd.io/substitute: disabled — filter those out before
# substituting so any runtime-only ${VAR} ref left in a resource isn't
# reported as unresolved. (hermes-hearth's WEBHOOK_SECRET no longer needs
# this — see #175 — but other apps may still opt out this way.)
SUBST_SCOPE='select((.metadata.annotations."kustomize.toolkit.fluxcd.io/substitute" // .metadata.labels."kustomize.toolkit.fluxcd.io/substitute" // "") != "disabled")'

# Python-based ${VAR} substitution (cross-platform, no envsubst dependency).
# Matches ${VAR} and ${VAR:=default} — resolves from env, keeps original if missing.
ENVSUBST_PY='
import sys, re, os
content = sys.stdin.read()
def sub(m):
    return os.environ.get(m.group(1), m.group(0))
sys.stdout.write(re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::[^}]*)?\}", sub, content))
'

# Homepage tags: every HTTPRoute says gethomepage.dev/enabled "true" or "false",
# and every gethomepage.dev/group (routes, plus Helm values rendered into
# ConfigMaps) is a group in homepage's layout.
HOMEPAGE_VALUES="$REPO_ROOT/kubernetes/infrastructure/homepage/values.yaml"
HOMEPAGE_GROUPS="$(yq eval '.config.settingsString' "$HOMEPAGE_VALUES" | yq eval '.layout | keys | .[]' -)"

# $1 = rendered manifests; prints each problem, returns 1 if there are any
check_homepage() {
  local untagged groups g bad=0
  untagged="$(printf '%s\n' "$1" | yq eval-all 'select(.kind == "HTTPRoute" and ((.metadata.annotations."gethomepage.dev/enabled" // "") | test("^(true|false)$") | not)) | .metadata.namespace + "/" + .metadata.name' - 2>/dev/null | grep -vE '^(---)?$' || true)"
  for r in $untagged; do
    echo "HTTPRoute $r has no gethomepage.dev/enabled \"true\" or \"false\""; bad=1
  done
  groups="$(printf '%s\n' "$1" | sed -nE 's/.*gethomepage\.dev\/group"?: *"?([^"]*)"?[[:space:]]*$/\1/p' | sort -u)"
  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    printf '%s\n' "$HOMEPAGE_GROUPS" | grep -Fxq -- "$g" \
      || { echo "group \"$g\" is not in the homepage layout"; bad=1; }
  done <<< "$groups"
  return "$bad"
}

# CNPG backup wiring (the #337/#339 bug class): every CNPG Cluster with a
# plugin backup story must have the barman-cloud plugin bound to an
# ObjectStore that exists in the same namespace, and every ObjectStore's
# S3 credentials must resolve to a Secret in the same build. Nothing here
# is schema-checkable — kubeconform passes all three failure modes.
# Input: rendered manifests as a YAML stream; yq converts to JSON.
check_cnpg_backups() {
  printf '%s\n' "$1" | yq eval-all -o=json '.' - 2>/dev/null | python3 -c '
import sys, json

METADATA_KEY = "metadata"
NAME_KEY = "name"

raw = sys.stdin.read()
# yq emits either a single JSON array or newline-separated JSON documents.
decoder = json.JSONDecoder()
docs = []
idx = 0
try:
    while idx < len(raw):
        while idx < len(raw) and raw[idx] in " \t\r\n":
            idx += 1
        if idx >= len(raw):
            break
        obj, end = decoder.raw_decode(raw, idx)
        docs.append(obj)
        idx = end
except Exception:
    sys.exit(0)  # unparseable stream: yq already handles real errors elsewhere

# Flatten: eval-all may nest arrays.
flat = []
def flatten(x):
    if isinstance(x, list):
        for i in x:
            flatten(i)
    elif isinstance(x, dict):
        flat.append(x)
for d in docs:
    flatten(d)

clusters, objectstores, secrets = [], [], []
seen = set()
for d in flat:
    key = (d.get("kind"), d.get("apiVersion"), json.dumps(d.get("metadata"), sort_keys=True))
    if key in seen:
        continue
    seen.add(key)
    k = d.get("kind") or ""
    av = d.get("apiVersion") or ""
    if k == "Cluster" and "postgresql.cnpg.io" in av:
        clusters.append(d)
    elif k == "ObjectStore" and "barmancloud.cnpg.io" in av:
        objectstores.append(d)
    elif k == "Secret":
        secrets.append(d)

errors = []
def ns(x):
    return ((x.get("metadata") or {}).get("namespace")) or ""

os_index = {(ns(o), (o.get("metadata") or {}).get("name")) for o in objectstores}
secret_index = set()
for s in secrets:
    secret_index.add((ns(s), (s.get("metadata") or {}).get("name")))

for c in clusters:
    ident = f"{ns(c)}/Cluster/{(c.get(METADATA_KEY) or {}).get(NAME_KEY)}"
    plugins = ((c.get("spec") or {}).get("plugins")) or []
    if not plugins:
        errors.append(f"{ident}: no spec.plugins — plugin backups fail \"cluster has no plugin configured\"")
        continue
    for p in plugins:
        if (p.get("name") or "") != "barman-cloud.cloudnative-pg.io":
            continue
        bound = (p.get("parameters") or {}).get("barmanObjectName")
        if not bound:
            errors.append(f"{ident}: barman-cloud plugin lacks parameters.barmanObjectName — daemon refuses lifecycle (no WAL, no backups)")
        elif (ns(c), bound) not in os_index:
            errors.append(f"{ident}: barmanObjectName {bound!r} has no ObjectStore in namespace {ns(c)!r} in this build")

for o in objectstores:
    ident = f"{ns(o)}/ObjectStore/{(o.get(METADATA_KEY) or {}).get(NAME_KEY)}"
    s3 = (((o.get("spec") or {}).get("configuration") or {}).get("s3Credentials")) or {}
    for field in ("accessKeyId", "secretAccessKey"):
        ref = s3.get(field) or {}
        name = ref.get("name")
        if not name:
            continue
        if (ns(o), name) not in secret_index:
            errors.append(f"{ident}: s3Credentials.{field} references Secret {name!r} not present in namespace {ns(o)!r} in this build")
        elif not ref.get("key"):
            errors.append(f"{ident}: s3Credentials.{field} has no key")
        else:
            # The #335 follow-up bug class: the Secret exists but its key value
            # was encrypted empty (silent awk failure), so barman gets
            # "Unable to locate credentials" at runtime.
            sec = next(s for s in secrets if ns(s) == ns(o) and (s.get("metadata") or {}).get("name") == name)
            data = {**(sec.get("data") or {}), **(sec.get("stringData") or {})}
            if data.get(ref.get("key"), "") in ("", None):
                errors.append(f"{ident}: Secret {name!r} key {ref.get('key')!r} is empty in this build")

for e in errors:
    print(e)
sys.exit(1 if errors else 0)
'
}

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

    if RENDERED="$(kustomize build "$BUILD_PATH" "${KUSTOMIZE_FLAGS[@]}" | yq eval "$SUBST_SCOPE" - | python3 -c "$ENVSUBST_PY")"; then
      # a successful build doesn't mean substitution succeeded — check for leftovers
      UNRESOLVED="$(printf '%s' "$RENDERED" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*(:[^}]*)?\}' | sort -u || true)"
      if [[ -n "$UNRESOLVED" ]]; then
        echo "  ✗ $name — unresolved variable(s):"
        echo "$UNRESOLVED" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
      elif HOMEPAGE_ERRORS="$(check_homepage "$RENDERED")" \
        && CNPG_ERRORS="$(check_cnpg_backups "$RENDERED")"; then
        echo "  ✓ $name"
      else
        echo "  ✗ $name — semantic checks:"
        if [[ -n "${HOMEPAGE_ERRORS:-}" ]]; then
          echo "$HOMEPAGE_ERRORS" | sed 's/^/      /'
        fi
        if [[ -n "${CNPG_ERRORS:-}" ]]; then
          echo "$CNPG_ERRORS" | sed 's/^/      /'
        fi
        HOMEPAGE_ERRORS=""
        CNPG_ERRORS=""
        FAILED=$((FAILED + 1))
      fi
    else
      echo "  ✗ $name — FAILED (re-running to show error):"
      kustomize build "$BUILD_PATH" "${KUSTOMIZE_FLAGS[@]}" \
        | yq eval "$SUBST_SCOPE" - \
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
