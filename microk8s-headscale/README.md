# MicroK8s Headscale package

This package deploys a single-node, hostpath-backed Headscale stack with Traefik as its only public entry point:

```text
UFW -> 80/tcp, 443/tcp, 3478/udp -> Traefik -> Headscale / Headplane
```

All Kubernetes services are `ClusterIP`. There is no MetalLB, NodePort, or direct public exposure of the Kubernetes API, Headscale metrics (`9090`), Headscale HTTP (`8080`), or Headplane (`3000`).

## Prerequisites and install

Use a supported single-node MicroK8s installation, root access, `openssl`, `curl`, and `envsubst` from `gettext-base`.

```bash
cp .env.example .env
vi .env
sudo ./install.sh
```

The installer checks MicroK8s, enables `dns`, `hostpath-storage`, and `helm3`, and enables the optional GPU addon only when `ENABLE_NVIDIA_GPU=true`. It connects to the native PostgreSQL instance configured by `HEADSCALE_DB_HOST`, `HEADSCALE_DB_PORT`, `HEADSCALE_DB_NAME`, and `HEADSCALE_DB_USER`. Set `HEADSCALE_DB_PASSWORD` only in the real `.env` or environment; it is never included in `.env.example`. The password is stored as a Kubernetes Secret. The deployment is idempotent.

The native PostgreSQL server must listen on the configured address and permit connections from the MicroK8s pod CIDR in `pg_hba.conf`. Restrict its firewall to the cluster network and verify connectivity before installation.

Do not automatically modify UFW. Expected public rules are:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3478/udp
```

## Access and private CA

```text
https://hs1.bitvividsolutions.com/       Headscale
https://hp1.bitvividsolutions.com/admin  Headplane
SERVER_IP:3478/udp       embedded DERP/STUN
```

Install `/opt/bitvivid-ca/bitvivid-root-ca.crt` on clients as a trusted root. Never distribute `/opt/bitvivid-ca/bitvivid-root-ca.key`. The root is not regenerated when it already exists.

## Verify and troubleshoot

```bash
./verify.sh
microk8s kubectl -n headscale logs deploy/headscale
microk8s kubectl -n traefik logs deploy/traefik
```

Verification checks MicroK8s, nodes, pods, services, both Traefik route kinds, HTTPS, the returned certificate, and Traefik service ports. Headscale’s embedded DERP/STUN listens on UDP `3478`; metrics remain internal on `9090`.

## Domains, Let's Encrypt, backups, and upgrades

For DNS names, set `HEADSCALE_HOST=headscale.example.com` and `HEADPLANE_HOST=headplane.example.com`, then rerun `install.sh`. Add `certResolver: letsencrypt` under each route’s `tls` block when ready for public certificates. Traefik persists ACME data on `microk8s-hostpath`; the HTTP challenge requires port 80. Do not use Let's Encrypt for an IP-only endpoint.

Back up the native PostgreSQL database, Headplane and Traefik ACME PVCs, Headscale private state, and `/opt/bitvivid-ca` (especially the root key). Pin/test image upgrades in `.env`, then rerun `install.sh`. Because PostgreSQL is external, it can later be replaced by a managed or HA PostgreSQL service without changing Headscale’s storage model.

`./uninstall.sh` removes workloads but preserves PVCs and CA material. `./uninstall.sh --purge` removes PVC data and the Headscale namespace, but still preserves `/opt/bitvivid-ca`, including its root private key. Delete that key manually only after confirming it is no longer needed.

## ACL warning

`headscale/acl.hujson` is deliberately permissive for initial testing. Tighten it before onboarding production users; it is a security policy, not a production default.
