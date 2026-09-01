#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); PACKAGE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ENV_FILE=${ENV_FILE:-"$PACKAGE_DIR/.env"}; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
TRAEFIK_NAMESPACE=${TRAEFIK_NAMESPACE:-traefik}; CA_DIR=/opt/bitvivid-ca
microk8s kubectl create namespace "$TRAEFIK_NAMESPACE" --dry-run=client -o yaml | microk8s kubectl apply -f -
microk8s kubectl -n "$TRAEFIK_NAMESPACE" create secret tls bitvivid-default-tls --cert="$CA_DIR/traefik-server.crt" --key="$CA_DIR/traefik-server.key" --dry-run=client -o yaml | microk8s kubectl apply -f -
