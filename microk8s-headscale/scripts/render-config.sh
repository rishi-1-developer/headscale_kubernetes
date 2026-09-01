#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); PACKAGE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ENV_FILE=${ENV_FILE:-"$PACKAGE_DIR/.env"}; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
: "${SERVER_IP:?SERVER_IP must be set in .env}"
HEADSCALE_NAMESPACE=${HEADSCALE_NAMESPACE:-headscale}; RENDERED_DIR=${RENDERED_DIR:-"$PACKAGE_DIR/.rendered"}
mkdir -p "$RENDERED_DIR"; command -v envsubst >/dev/null || { echo 'envsubst is required (install gettext-base)' >&2; exit 1; }
envsubst < "$PACKAGE_DIR/headscale/config.yaml.template" > "$RENDERED_DIR/headscale-config.yaml"
envsubst < "$PACKAGE_DIR/headplane/config.yaml.template" > "$RENDERED_DIR/headplane-config.yaml"
for item in headscale/deployment.yaml headplane/deployment.yaml headplane/secret.yaml headscale/routes.yaml headplane/routes.yaml traefik/default-tls-store.yaml; do
  out=$(basename "${item}"); envsubst < "$PACKAGE_DIR/${item}.template" > "$RENDERED_DIR/$out"
done
microk8s kubectl -n "$HEADSCALE_NAMESPACE" create configmap headscale-config --from-file=config.yaml="$RENDERED_DIR/headscale-config.yaml" --from-file=acl.hujson="$PACKAGE_DIR/headscale/acl.hujson" --dry-run=client -o yaml | microk8s kubectl apply -f -
microk8s kubectl -n "$HEADSCALE_NAMESPACE" create configmap headplane-config --from-file=config.yaml="$RENDERED_DIR/headplane-config.yaml" --dry-run=client -o yaml | microk8s kubectl apply -f -
