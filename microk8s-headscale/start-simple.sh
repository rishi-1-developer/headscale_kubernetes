#!/usr/bin/env bash
set -euo pipefail
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE=${ENV_FILE:-"$BASE_DIR/.env"}
[[ -f "$ENV_FILE" ]] || { echo "Copy .env.simple.example to .env." >&2; exit 1; }
source "$ENV_FILE"
HEADSCALE_NAMESPACE=${HEADSCALE_NAMESPACE:-headscale}; INGRESS_CLASS_NAME=${INGRESS_CLASS_NAME:-nginx}; TLS_SECRET_NAME=${TLS_SECRET_NAME:-headscale-tls}
HEADSCALE_DB_HOST=${HEADSCALE_DB_HOST:-127.0.0.1}; HEADSCALE_DB_PORT=${HEADSCALE_DB_PORT:-5432}; HEADSCALE_DB_NAME=${HEADSCALE_DB_NAME:-headscale}; HEADSCALE_DB_USER=${HEADSCALE_DB_USER:-headscale}
: "${HEADSCALE_DB_PASSWORD:?Set HEADSCALE_DB_PASSWORD in .env}"
HEADPLANE_COOKIE_SECRET=${HEADPLANE_COOKIE_SECRET:-}
HEADSCALE_API_KEY=${HEADSCALE_API_KEY:-}
export HEADSCALE_NAMESPACE INGRESS_CLASS_NAME TLS_SECRET_NAME HEADSCALE_IMAGE HEADPLANE_IMAGE HEADSCALE_HOST HEADPLANE_HOST HEADSCALE_DB_HOST HEADSCALE_DB_PORT HEADSCALE_DB_NAME HEADSCALE_DB_USER HEADSCALE_DB_PASSWORD
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT
envsubst < "$BASE_DIR/headscale/namespace.yaml" | microk8s kubectl apply -f -
if microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headscale-secrets >/dev/null 2>&1; then
  HEADPLANE_COOKIE_SECRET=$(microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headscale-secrets -o jsonpath='{.data.cookie-secret}' | base64 -d)
  HEADSCALE_API_KEY=$(microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headscale-secrets -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d || true)
else
  if [[ -z "$HEADPLANE_COOKIE_SECRET" ]]; then HEADPLANE_COOKIE_SECRET=$(openssl rand -hex 32); fi
  microk8s kubectl -n "$HEADSCALE_NAMESPACE" create secret generic headscale-secrets --from-literal=db-password="$HEADSCALE_DB_PASSWORD" --from-literal=cookie-secret="$HEADPLANE_COOKIE_SECRET" --dry-run=client -o yaml | microk8s kubectl apply -f -
fi
if [[ -n "${TLS_CERT_FILE:-}" && -n "${TLS_KEY_FILE:-}" ]]; then
  microk8s kubectl -n "$HEADSCALE_NAMESPACE" create secret tls "$TLS_SECRET_NAME" --cert="$TLS_CERT_FILE" --key="$TLS_KEY_FILE" --dry-run=client -o yaml | microk8s kubectl apply -f -
fi
envsubst < "$BASE_DIR/headscale/config.yaml.template" > "$TMP_DIR/headscale-config.yaml"
microk8s kubectl -n "$HEADSCALE_NAMESPACE" create configmap headscale-config --from-file=config.yaml="$TMP_DIR/headscale-config.yaml" --from-file=acl.hujson="$BASE_DIR/headscale/acl.hujson" --dry-run=client -o yaml | microk8s kubectl apply -f -
for f in headscale/deployment.yaml headscale/service.yaml headscale/pvc.yaml; do
  src="$BASE_DIR/$f"; [[ -f "$src" ]] || src="${src%.yaml}.yaml.template"
  envsubst < "$src" | microk8s kubectl apply -f -
done
microk8s kubectl -n "$HEADSCALE_NAMESPACE" rollout status deploy/headscale --timeout=180s
if [[ -z "${HEADSCALE_API_KEY:-}" ]]; then
  HEADSCALE_API_KEY=$(microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headscale-secrets -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d || true)
fi
if [[ -z "$HEADSCALE_API_KEY" ]]; then
  HEADSCALE_API_KEY=$(microk8s kubectl -n "$HEADSCALE_NAMESPACE" exec deploy/headscale -- headscale apikeys create --expiration 365d | tail -n 1)
fi
export HEADPLANE_COOKIE_SECRET HEADSCALE_API_KEY
microk8s kubectl -n "$HEADSCALE_NAMESPACE" create secret generic headscale-secrets --from-literal=db-password="$HEADSCALE_DB_PASSWORD" --from-literal=cookie-secret="$HEADPLANE_COOKIE_SECRET" --from-literal=api-key="$HEADSCALE_API_KEY" --dry-run=client -o yaml | microk8s kubectl apply -f -
envsubst < "$BASE_DIR/headplane/config.yaml.template" > "$TMP_DIR/headplane-config.yaml"
microk8s kubectl -n "$HEADSCALE_NAMESPACE" create configmap headplane-config --from-file=config.yaml="$TMP_DIR/headplane-config.yaml" --dry-run=client -o yaml | microk8s kubectl apply -f -
for f in headplane/deployment.yaml headplane/service.yaml headplane/pvc.yaml; do
  src="$BASE_DIR/$f"; [[ -f "$src" ]] || src="${src%.yaml}.yaml.template"
  envsubst < "$src" | microk8s kubectl apply -f -
done
envsubst < "$BASE_DIR/k8s/ingress.yaml.template" | microk8s kubectl apply -f -
microk8s kubectl -n "$HEADSCALE_NAMESPACE" rollout status deploy/headplane --timeout=180s
