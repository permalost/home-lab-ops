#!/usr/bin/env bash
# Scaffold a new app under kubernetes/apps/<name>/ and a cluster shell
# under kubernetes/clusters/<cluster>/<name>.yaml.
#
# Usage:
#   new-app.sh NAME=<name> SUBDOMAIN=<subdomain> IMAGE=<image> [CLUSTER=orion] [DEPENDS_ON=<dep>]
#
# Example:
#   new-app.sh NAME=homebox SUBDOMAIN=homebox IMAGE=ghcr.io/sysadminsmedia/homebox:0.20.2

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAME=""
SUBDOMAIN=""
IMAGE=""
CLUSTER="orion"
DEPENDS_ON=""

for arg in "$@"; do
  case "$arg" in
    NAME=*)       NAME="${arg#NAME=}" ;;
    SUBDOMAIN=*)  SUBDOMAIN="${arg#SUBDOMAIN=}" ;;
    IMAGE=*)      IMAGE="${arg#IMAGE=}" ;;
    CLUSTER=*)    CLUSTER="${arg#CLUSTER=}" ;;
    DEPENDS_ON=*) DEPENDS_ON="${arg#DEPENDS_ON=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ -z "$NAME" || -z "$SUBDOMAIN" || -z "$IMAGE" ]]; then
  echo "Usage: $0 NAME=<name> SUBDOMAIN=<subdomain> IMAGE=<image> [CLUSTER=orion] [DEPENDS_ON=<dep>]" >&2
  exit 1
fi

if [[ "$IMAGE" == *:* ]]; then
  IMAGE_NAME="${IMAGE%:*}"
  IMAGE_TAG="${IMAGE##*:}"
else
  IMAGE_NAME="$IMAGE"
  IMAGE_TAG="latest"
fi

APP_DIR="${REPO_ROOT}/kubernetes/apps/${NAME}"
SHELL_FILE="${REPO_ROOT}/kubernetes/clusters/${CLUSTER}/${NAME}.yaml"
APP_TMPL="${REPO_ROOT}/kubernetes/apps/_template/kustomization.yaml.tmpl"
SHELL_TMPL="${REPO_ROOT}/kubernetes/clusters/_template/app.yaml.tmpl"

if [[ -d "$APP_DIR" ]]; then
  echo "ERROR: ${APP_DIR} already exists. Choose a different name or edit it directly." >&2
  exit 1
fi

if [[ -f "$SHELL_FILE" ]]; then
  echo "ERROR: ${SHELL_FILE} already exists." >&2
  exit 1
fi

CLUSTER_DIR="${REPO_ROOT}/kubernetes/clusters/${CLUSTER}"
if [[ ! -d "$CLUSTER_DIR" ]]; then
  echo "ERROR: cluster directory ${CLUSTER_DIR} does not exist" >&2
  exit 1
fi

mkdir -p "$APP_DIR"

sed \
  -e "s|__NAME__|${NAME}|g" \
  -e "s|__SUBDOMAIN__|${SUBDOMAIN}|g" \
  -e "s|__IMAGE__|${IMAGE_NAME}|g" \
  -e "s|__IMAGE_TAG__|${IMAGE_TAG}|g" \
  "$APP_TMPL" > "${APP_DIR}/kustomization.yaml"

SHELL_CONTENT=$(sed \
  -e "s|__NAME__|${NAME}|g" \
  -e "s|__SUBDOMAIN__|${SUBDOMAIN}|g" \
  "$SHELL_TMPL")

if [[ -n "$DEPENDS_ON" ]]; then
  SHELL_CONTENT=$(echo "$SHELL_CONTENT" | sed \
    -e "s|# - name: __DEPENDS_ON__.*|  - name: ${DEPENDS_ON}|")
else
  SHELL_CONTENT=$(echo "$SHELL_CONTENT" | grep -v "# - name: __DEPENDS_ON__")
fi

echo "$SHELL_CONTENT" > "$SHELL_FILE"

echo ""
echo "Scaffolded:"
echo "  ${APP_DIR}/kustomization.yaml"
echo "  ${SHELL_FILE}"
echo ""
echo "Next steps:"
echo "  1. Edit ${APP_DIR}/kustomization.yaml — set the correct image tag, port patches, and any extra resources."
echo "  2. Edit ${SHELL_FILE} — confirm dependsOn and postBuild.substitute values."
echo "  3. If this service needs secrets:"
echo "       cp /dev/null ${APP_DIR}/secret.sops.yaml"
echo "       # add stringData keys, then:"
echo "       sops --encrypt --in-place ${APP_DIR}/secret.sops.yaml"
echo "       # add secret.sops.yaml to resources in kustomization.yaml"
echo "  4. Run: task gen:validate"
