#!/usr/bin/env bash
# Diffs the rendered manifests of every webapp/base consumer between a base
# git ref and the working tree.
#
# Usage: scripts/webapp-render-diff.sh [base-ref]
#   base-ref: git ref to diff against (default: main)
#
# Consumers are discovered dynamically — any kustomization whose resources or
# components transitively include kubernetes/apps/webapp/base — in both the
# base ref and the working tree, so added and removed consumers are picked up
# without a hardcoded list. Renders use the same load restrictor as
# scripts/validate.sh, since consumers reference the base outside their own
# root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF="${1:-main}"
WEBAPP_BASE="kubernetes/apps/webapp/base"

command -v kustomize >/dev/null 2>&1 || { echo "ERROR: kustomize not found. Run: task gen:tools" >&2; exit 1; }
git -C "$REPO_ROOT" rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null ||
  { echo "ERROR: base ref not found: $BASE_REF" >&2; exit 1; }

# ── Consumer discovery ───────────────────────────────────────────────────────

# Prints "<dir>\t<ref>" for every resources:/components: entry of every
# kustomization under kubernetes/ that could be a directory reference (no
# colon, no .yaml/.json suffix). Block-style lists only — the repo has no
# flow-style resources.
list_refs() {
  local tree="$1" dir
  (cd "$tree" && find kubernetes -type f -name kustomization.yaml -print0) |
    while IFS= read -r -d '' file; do
      dir="${file%/*}"
      [[ "$file" == */* ]] || dir="."
      awk -v dir="$dir" '
        inblock && /^[[:alnum:]_-]+:/ { inblock = 0 }
        /^(resources|components):[[:space:]]*$/ { inblock = 1; next }
        inblock && /^[[:space:]]*-[[:space:]]*/ {
          ref = $0
          sub(/^[[:space:]]*-[[:space:]]*/, "", ref)
          sub(/[[:space:]]+#.*$/, "", ref)
          if (ref != "" && ref !~ /[:#]/ && ref !~ /\.(ya?ml|json)$/) print dir "\t" ref
        }
      ' "$tree/$file"
    done
}

# Resolves a kustomization dir + relative ref to a tree-relative path; prints
# nothing when the ref does not resolve to an existing directory.
resolve_ref() {
  local abs
  abs="$(realpath -m --relative-to="$1" "$1/$2/$3")"
  case "$abs" in ..*) return 0 ;; esac
  [[ -d "$1/$abs" ]] && printf '%s\n' "$abs"
  return 0
}

# Prints the sorted tree-relative dirs of every kustomization that
# transitively includes webapp/base.
discover_consumers() {
  local tree="$1" dir ref resolved changed
  declare -A refs=()
  declare -A consumer=()
  while IFS=$'\t' read -r dir ref; do
    resolved="$(resolve_ref "$tree" "$dir" "$ref")" || continue
    [[ -n "$resolved" ]] || continue
    refs["$dir"]="${refs[$dir]:-} $resolved"
  done < <(list_refs "$tree")

  changed=1
  while (( changed )); do
    changed=0
    for dir in "${!refs[@]}"; do
      [[ -n "${consumer[$dir]:-}" ]] && continue
      for ref in ${refs[$dir]}; do
        if [[ "$ref" == "$WEBAPP_BASE" || -n "${consumer[$ref]:-}" ]]; then
          consumer["$dir"]=1
          changed=1
          break
        fi
      done
    done
  done

  if (( ${#consumer[@]} > 0 )); then
    printf '%s\n' "${!consumer[@]}" | sort
  fi
  return 0
}

# ── Render and diff ──────────────────────────────────────────────────────────

# Renders one consumer to a file; a missing dir renders as empty so added and
# removed consumers still produce a diff.
render() {
  local tree="$1" consumer="$2" out="$3" label="$4"
  if [[ ! -d "$tree/$consumer" ]]; then
    : > "$out"
    return 0
  fi
  if ! kustomize build --load-restrictor=LoadRestrictionsNone "$tree/$consumer" > "$out" 2> "$out.err"; then
    echo "ERROR: kustomize build failed for $consumer ($label):" >&2
    sed 's/^/  /' "$out.err" >&2
    return 1
  fi
  rm -f "$out.err"
  return 0
}

TMP="$(mktemp -d)"
trap 'git -C "$REPO_ROOT" worktree remove --force "$TMP/base-tree" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

git -C "$REPO_ROOT" worktree add --detach --quiet "$TMP/base-tree" "$BASE_REF" >/dev/null

consumers="$( { discover_consumers "$TMP/base-tree"; discover_consumers "$REPO_ROOT"; } | sort -u )"
[[ -n "$consumers" ]] || { echo "ERROR: no webapp/base consumers found" >&2; exit 1; }

total=0
changed=0
failed=0
while IFS= read -r c; do
  total=$((total + 1))
  render "$TMP/base-tree" "$c" "$TMP/a.yaml" "base ref $BASE_REF" || { failed=$((failed + 1)); continue; }
  render "$REPO_ROOT" "$c" "$TMP/b.yaml" "working tree" || { failed=$((failed + 1)); continue; }
  rc=0
  out="$(diff -u --label "a/$c" --label "b/$c" "$TMP/a.yaml" "$TMP/b.yaml")" || rc=$?
  if (( rc == 0 )); then
    echo "=== $c: no change"
  elif (( rc == 1 )); then
    changed=$((changed + 1))
    echo "=== $c: changed"
    printf '%s\n' "$out"
  else
    echo "ERROR: diff failed for $c (exit $rc)" >&2
    failed=$((failed + 1))
  fi
done <<< "$consumers"

echo
echo "SUMMARY: $total consumers — $changed changed, $((total - changed - failed)) no change (base ref: $BASE_REF, head: working tree)"
(( failed == 0 )) || exit 1
