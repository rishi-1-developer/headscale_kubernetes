#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ENV_FILE=${ENV_FILE:-"$PACKAGE_DIR/.env"}
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
: "${SERVER_IP:?SERVER_IP must be set in .env}"
CA_DIR=/opt/bitvivid-ca
mkdir -p "$CA_DIR"; chmod 700 "$CA_DIR"
CA_ORGANIZATION=${CA_ORGANIZATION:-Bitvivid}; CA_COMMON_NAME=${CA_COMMON_NAME:-Bitvivid Root CA}
CA_VALIDITY_DAYS=${CA_VALIDITY_DAYS:-3650}; SERVER_CERT_VALIDITY_DAYS=${SERVER_CERT_VALIDITY_DAYS:-1825}
if [[ ! -s "$CA_DIR/bitvivid-root-ca.key" || ! -s "$CA_DIR/bitvivid-root-ca.crt" ]]; then
  openssl genrsa -out "$CA_DIR/bitvivid-root-ca.key" 4096
  chmod 600 "$CA_DIR/bitvivid-root-ca.key"
  openssl req -x509 -new -nodes -key "$CA_DIR/bitvivid-root-ca.key" -sha256 -days "$CA_VALIDITY_DAYS" -subj "/O=$CA_ORGANIZATION/CN=$CA_COMMON_NAME" -out "$CA_DIR/bitvivid-root-ca.crt"
fi
if [[ ! -s "$CA_DIR/traefik-server.key" || ! -s "$CA_DIR/traefik-server.crt" ]]; then
  openssl genrsa -out "$CA_DIR/traefik-server.key" 2048
  chmod 600 "$CA_DIR/traefik-server.key"
  openssl req -new -key "$CA_DIR/traefik-server.key" -subj "/O=$CA_ORGANIZATION/CN=$SERVER_IP" -out "$CA_DIR/traefik-server.csr"
  printf 'subjectAltName = IP:%s\nextendedKeyUsage = serverAuth\n' "$SERVER_IP" > "$CA_DIR/server-ext.cnf"
  openssl x509 -req -in "$CA_DIR/traefik-server.csr" -CA "$CA_DIR/bitvivid-root-ca.crt" -CAkey "$CA_DIR/bitvivid-root-ca.key" -CAcreateserial -out "$CA_DIR/traefik-server.crt" -days "$SERVER_CERT_VALIDITY_DAYS" -sha256 -extfile "$CA_DIR/server-ext.cnf"
  rm -f "$CA_DIR/traefik-server.csr" "$CA_DIR/bitvivid-root-ca.srl" "$CA_DIR/server-ext.cnf"
fi
echo "Client certificate to distribute:"; echo "    $CA_DIR/bitvivid-root-ca.crt"
echo; echo "KEEP PRIVATE:"; echo "    $CA_DIR/bitvivid-root-ca.key"
