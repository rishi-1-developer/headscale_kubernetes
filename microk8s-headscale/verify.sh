#!/usr/bin/env bash
set -u
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ENV_FILE=${ENV_FILE:-"$SCRIPT_DIR/.env"}; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
HEADSCALE_NAMESPACE=${HEADSCALE_NAMESPACE:-headscale}; TRAEFIK_NAMESPACE=${TRAEFIK_NAMESPACE:-traefik}
microk8s status || true; microk8s kubectl get nodes || true; microk8s kubectl get pods -n "$TRAEFIK_NAMESPACE" || true
microk8s kubectl get pods -n "$HEADSCALE_NAMESPACE" || true; microk8s kubectl get svc -n "$HEADSCALE_NAMESPACE" || true
microk8s kubectl get ingressroute -A || true; microk8s kubectl get ingressrouteudp -A || true
if [[ -n ${SERVER_IP:-} ]]; then
  curl -kfsS --connect-timeout 5 "https://$SERVER_IP" >/dev/null && echo 'HTTPS endpoint: OK' || echo 'HTTPS endpoint: unavailable'
  timeout 8 openssl s_client -connect "$SERVER_IP:443" -servername "$SERVER_IP" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null || true
  microk8s kubectl -n "$TRAEFIK_NAMESPACE" get svc traefik -o jsonpath='UDP/TCP service ports: {.spec.ports[*].port}{"\n"}' || true
fi
