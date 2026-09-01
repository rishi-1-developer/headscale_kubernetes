#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ENV_FILE=${ENV_FILE:-"$SCRIPT_DIR/.env"}
[[ -f "$ENV_FILE" ]] || { echo "Copy .env.example to .env and edit it." >&2; exit 1; }; source "$ENV_FILE"
: "${SERVER_IP:?SERVER_IP must be set in .env}"
[[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo 'SERVER_IP must be an IPv4 address.' >&2; exit 1; }
HEADSCALE_NAMESPACE=${HEADSCALE_NAMESPACE:-headscale}; TRAEFIK_NAMESPACE=${TRAEFIK_NAMESPACE:-traefik}
HEADSCALE_HOST=${HEADSCALE_HOST:-$SERVER_IP}; HEADPLANE_HOST=${HEADPLANE_HOST:-$SERVER_IP}
HEADSCALE_DB_HOST=${HEADSCALE_DB_HOST:-$SERVER_IP}; HEADSCALE_DB_PORT=${HEADSCALE_DB_PORT:-5432}
HEADSCALE_DB_NAME=${HEADSCALE_DB_NAME:-headscale}; HEADSCALE_DB_USER=${HEADSCALE_DB_USER:-headscale}
export SERVER_IP HEADSCALE_NAMESPACE TRAEFIK_NAMESPACE LETSENCRYPT_EMAIL HEADSCALE_IMAGE HEADPLANE_IMAGE HEADSCALE_BASE_DOMAIN HEADSCALE_HOST HEADPLANE_HOST HEADSCALE_DB_HOST HEADSCALE_DB_PORT HEADSCALE_DB_NAME HEADSCALE_DB_USER
export CA_ORGANIZATION CA_COMMON_NAME CA_VALIDITY_DAYS SERVER_CERT_VALIDITY_DAYS
command -v microk8s >/dev/null || { echo 'MicroK8s is not installed.' >&2; exit 1; }; microk8s status --wait-ready
for addon in dns hostpath-storage helm3; do
  microk8s enable "$addon"
done
[[ "${ENABLE_NVIDIA_GPU:-false}" == true ]] && microk8s enable gpu
envsubst < "$SCRIPT_DIR/headscale/namespace.yaml" | microk8s kubectl apply -f -
"$SCRIPT_DIR/scripts/create-ca.sh"; "$SCRIPT_DIR/scripts/install-ca-secret.sh"
if microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headscale-db >/dev/null 2>&1; then
  export HEADSCALE_DB_PASSWORD=$(microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headscale-db -o jsonpath='{.data.password}' | base64 -d)
else
  : "${HEADSCALE_DB_PASSWORD:?Set HEADSCALE_DB_PASSWORD in .env or the environment; it is never stored in .env.example}"
  microk8s kubectl -n "$HEADSCALE_NAMESPACE" create secret generic headscale-db --from-literal=password="$HEADSCALE_DB_PASSWORD" --dry-run=client -o yaml | microk8s kubectl apply -f -
fi
export HEADSCALE_DB_PASSWORD
if microk8s kubectl get ingressclass traefik >/dev/null 2>&1; then
  EXISTING_TRAEFIK_NAMESPACE=$(microk8s kubectl get ingressclass traefik -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}')
  if [[ -n "$EXISTING_TRAEFIK_NAMESPACE" && "$EXISTING_TRAEFIK_NAMESPACE" != "$TRAEFIK_NAMESPACE" ]]; then
    echo "Traefik already belongs to Helm namespace '$EXISTING_TRAEFIK_NAMESPACE', but TRAEFIK_NAMESPACE='$TRAEFIK_NAMESPACE'." >&2
    echo "Set TRAEFIK_NAMESPACE=$EXISTING_TRAEFIK_NAMESPACE in .env and rerun install.sh." >&2
    exit 1
  fi
fi
microk8s helm3 repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true; microk8s helm3 repo update
mkdir -p "$SCRIPT_DIR/.rendered"; envsubst < "$SCRIPT_DIR/traefik/values.yaml.template" > "$SCRIPT_DIR/.rendered/traefik-values.yaml"
microk8s helm3 upgrade --install traefik traefik/traefik -n "$TRAEFIK_NAMESPACE" --create-namespace -f "$SCRIPT_DIR/.rendered/traefik-values.yaml" --wait
export RENDERED_DIR="$SCRIPT_DIR/.rendered"; "$SCRIPT_DIR/scripts/render-config.sh"
microk8s kubectl apply -f "$SCRIPT_DIR/.rendered/headscale-deployment.yaml"; microk8s kubectl -n "$HEADSCALE_NAMESPACE" rollout status deploy/headscale --timeout=180s
if ! microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headplane-secret >/dev/null 2>&1; then
  HEADPLANE_COOKIE_SECRET=$(openssl rand -hex 32); HEADSCALE_API_KEY=$(microk8s kubectl -n "$HEADSCALE_NAMESPACE" exec deploy/headscale -- headscale apikeys create --expiration 365d | tail -n 1); export HEADPLANE_COOKIE_SECRET HEADSCALE_API_KEY
  "$SCRIPT_DIR/scripts/render-config.sh"; microk8s kubectl apply -f "$SCRIPT_DIR/.rendered/headplane-secret.yaml"
else
  export HEADPLANE_COOKIE_SECRET=$(microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headplane-secret -o jsonpath='{.data.cookie-secret}' | base64 -d)
  export HEADSCALE_API_KEY=$(microk8s kubectl -n "$HEADSCALE_NAMESPACE" get secret headplane-secret -o jsonpath='{.data.api-key}' | base64 -d)
fi
microk8s kubectl apply -f "$SCRIPT_DIR/.rendered/headplane-deployment.yaml" -f "$SCRIPT_DIR/.rendered/default-tls-store.yaml" -f "$SCRIPT_DIR/.rendered/headscale-routes.yaml" -f "$SCRIPT_DIR/.rendered/headplane-routes.yaml"
"$SCRIPT_DIR/verify.sh" || true; echo "Access: https://$SERVER_IP/ and https://$SERVER_IP/admin"
