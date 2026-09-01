#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ENV_FILE=${ENV_FILE:-"$SCRIPT_DIR/.env"}; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
HEADSCALE_NAMESPACE=${HEADSCALE_NAMESPACE:-headscale}; TRAEFIK_NAMESPACE=${TRAEFIK_NAMESPACE:-traefik}
microk8s kubectl -n "$HEADSCALE_NAMESPACE" delete ingressroute,ingressrouteudp,middleware --all --ignore-not-found
microk8s kubectl -n "$HEADSCALE_NAMESPACE" delete deploy,svc,configmap,secret --all --ignore-not-found
microk8s helm3 uninstall traefik -n "$TRAEFIK_NAMESPACE" --ignore-not-found || true
if [[ ${1:-} == --purge ]]; then
  microk8s kubectl -n "$HEADSCALE_NAMESPACE" delete pvc --all --ignore-not-found; microk8s kubectl delete namespace "$HEADSCALE_NAMESPACE" --ignore-not-found
  echo 'PVC data removed. /opt/bitvivid-ca and its private key were preserved.'
else echo 'Kubernetes workloads removed; PVCs and /opt/bitvivid-ca were preserved.'; fi
