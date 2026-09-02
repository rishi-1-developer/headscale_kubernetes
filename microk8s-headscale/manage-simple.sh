#!/usr/bin/env bash
set -euo pipefail
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ENV_FILE=${ENV_FILE:-"$BASE_DIR/.env"}; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
HEADSCALE_NAMESPACE=${HEADSCALE_NAMESPACE:-headscale}
case "${1:-status}" in
  start) "$BASE_DIR/start-simple.sh" ;;
  stop) microk8s kubectl -n "$HEADSCALE_NAMESPACE" scale deploy/headscale deploy/headplane --replicas=0 ;;
  start-services) microk8s kubectl -n "$HEADSCALE_NAMESPACE" scale deploy/headscale deploy/headplane --replicas=1 ;;
  recreate) microk8s kubectl -n "$HEADSCALE_NAMESPACE" rollout restart deploy/headscale deploy/headplane ;;
  status) microk8s kubectl get deploy,pods,svc,pvc,ingress -n "$HEADSCALE_NAMESPACE" ;;
  logs-headscale) microk8s kubectl logs -n "$HEADSCALE_NAMESPACE" deploy/headscale -f ;;
  logs-headplane) microk8s kubectl logs -n "$HEADSCALE_NAMESPACE" deploy/headplane -f ;;
  upgrade-headscale) microk8s kubectl -n "$HEADSCALE_NAMESPACE" set image deploy/headscale headscale="$2" ;;
  upgrade-headplane) microk8s kubectl -n "$HEADSCALE_NAMESPACE" set image deploy/headplane headplane="$2" ;;
  *) echo "Usage: $0 {start|stop|start-services|recreate|status|logs-headscale|logs-headplane|upgrade-headscale IMAGE|upgrade-headplane IMAGE}" >&2; exit 2 ;;
esac
