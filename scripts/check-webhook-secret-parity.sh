#!/usr/bin/env bash
# hermes-hearth's WEBHOOK_SECRET and vkms's alertmanager-hermes token must be
# byte-identical (Alertmanager sends the latter as an auth header; Hermes
# checks it against the former) but live in two separately-encrypted SOPS
# files with no other link between them. Drift = silent 401s (see #175).
#
# Usage: scripts/check-webhook-secret-parity.sh
# Requires SOPS_AGE_KEY_FILE; skips with a warning if unset (mirrors
# flux-build.sh's handling of the same prerequisite).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_SECRET="$REPO_ROOT/kubernetes/apps/hermes-hearth/secret.yaml"
AM_SECRET="$REPO_ROOT/kubernetes/infrastructure/vkms/alertmanager-hermes.sops.yaml"

if [[ -z "${SOPS_AGE_KEY_FILE:-}" || ! -f "${SOPS_AGE_KEY_FILE:-}" ]]; then
  echo "WARN  SOPS_AGE_KEY_FILE not set — skipping webhook secret parity check"
  exit 0
fi

a="$(sops -d --extract '["stringData"]["hermesWebhookSecret"]' "$HERMES_SECRET")"
b="$(sops -d --extract '["stringData"]["token"]' "$AM_SECRET")"

if [[ "$a" != "$b" ]]; then
  echo "ERROR  hermes-hearth's hermesWebhookSecret and vkms's alertmanager-hermes token have drifted." >&2
  echo "       $HERMES_SECRET (hermesWebhookSecret)" >&2
  echo "       $AM_SECRET (token)" >&2
  echo "       Alertmanager's alerts to Hermes will silently 401 until these match." >&2
  exit 1
fi

echo "INFO  webhook secret parity OK"
