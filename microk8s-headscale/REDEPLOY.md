# Headscale and Headplane redeployment guide

This is the final simplified deployment path. It uses existing MicroK8s and an existing Traefik controller with IngressClass public. Headscale and Headplane run as separate Deployments with ClusterIP Services, hostpath PVCs, external PostgreSQL, and Keycloak OIDC.

Use start-simple.sh and manage-simple.sh. The older install.sh, uninstall.sh, verify.sh, and traefik directory are legacy files and are not part of this workflow.

## Requirements

- MicroK8s and kubectl
- Traefik watching IngressClass public
- envsubst from gettext-base
- openssl
- Native PostgreSQL reachable from the Headscale Pod
- DNS records for hs1.bitvividsolutions.com and hp1.bitvividsolutions.com
- A Keycloak realm and confidential OpenID Connect client

Check:

~~~bash
microk8s status --wait-ready
kubectl get ingressclass public
kubectl get pods -n ingress
~~~

## PostgreSQL

Create the database and user in native PostgreSQL:

~~~sql
CREATE DATABASE headscale;
CREATE USER headscale WITH ENCRYPTED PASSWORD 'REPLACE_ME';
GRANT ALL PRIVILEGES ON DATABASE headscale TO headscale;
\c headscale
GRANT ALL ON SCHEMA public TO headscale;
~~~

Set PostgreSQL to listen on the configured address. Add the MicroK8s Pod CIDR to pg_hba.conf. The Headscale template uses SSL:

~~~text
hostssl headscale headscale 10.1.0.0/16 scram-sha-256
~~~

Replace the CIDR with the actual Pod CIDR, restrict the PostgreSQL firewall to the cluster network, and reload:

~~~bash
sudo systemctl reload postgresql
~~~

## DNS, TLS, and firewall

Point both names to the public IP handled by Traefik:

~~~text
hs1.bitvividsolutions.com  A  YOUR_PUBLIC_IP
hp1.bitvividsolutions.com  A  YOUR_PUBLIC_IP
~~~

Open:

~~~bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3478/udp
~~~

The Ingress uses Traefik's websecure entrypoint and letsencrypt resolver. Optionally set TLS_CERT_FILE and TLS_KEY_FILE in .env to create a Kubernetes TLS Secret from existing certificate files.

## Keycloak

Create a confidential OpenID Connect client:

- Client authentication: enabled
- Standard flow: enabled
- Redirect URI: https://hp1.bitvividsolutions.com/admin/oidc/callback
- Web origin: https://hp1.bitvividsolutions.com

The issuer is the Keycloak realm issuer, for example:

~~~text
https://keycloak.example.com/realms/company
~~~

Ensure tokens contain sub, email, and preferably name or preferred_username.

## Environment

~~~bash
cp .env.simple.example .env
chmod 600 .env
~~~

Edit .env:

~~~bash
HEADSCALE_HOST=hs1.bitvividsolutions.com
HEADPLANE_HOST=hp1.bitvividsolutions.com
INGRESS_CLASS_NAME=public

HEADSCALE_DB_HOST=10.155.155.7
HEADSCALE_DB_PORT=5432
HEADSCALE_DB_NAME=headscale
HEADSCALE_DB_USER=postgres
HEADSCALE_DB_PASSWORD=REPLACE_ME

KEYCLOAK_ISSUER=https://keycloak.example.com/realms/company
KEYCLOAK_CLIENT_ID=headplane
KEYCLOAK_CLIENT_SECRET=REPLACE_ME
~~~

Do not commit .env or put secrets in .env.simple.example. The script generates a valid 32-character Headplane cookie secret if one is not already stored.

## Fresh deployment or redeployment

Run:

~~~bash
./start-simple.sh
~~~

The script applies the namespace, creates Kubernetes Secrets, renders ConfigMaps, applies the Headscale Deployment/Service/PVC, waits for Headscale, creates or reuses the Headscale API key, applies Headplane, and applies the Ingress.

The Headscale PVC stores the Noise and embedded DERP private keys. Keep it across redeployments.

Verify:

~~~bash
kubectl get deploy,pods,svc,pvc,ingress -n headscale
kubectl logs -n headscale deploy/headscale
kubectl logs -n headscale deploy/headplane
~~~

Open:

~~~text
https://hp1.bitvividsolutions.com/admin
~~~

The first successful OIDC user becomes Headplane owner.

## Secrets

Kubernetes Secret headscale-secrets contains db-password, cookie-secret, api-key, and client-secret.

~~~bash
kubectl describe secret headscale-secrets -n headscale
~~~

Do not print or share Secret values. If an API key or Keycloak secret is exposed, revoke and replace it.

## Operations

~~~bash
./manage-simple.sh status
./manage-simple.sh stop
./manage-simple.sh start-services
./manage-simple.sh recreate
./manage-simple.sh logs-headscale
./manage-simple.sh logs-headplane
~~~

Stop scales both applications to zero. Recreate restarts them without deleting state.

## Upgrades

~~~bash
./manage-simple.sh upgrade-headscale ghcr.io/juanfont/headscale:0.27.1
./manage-simple.sh upgrade-headplane ghcr.io/tale/headplane:0.6.1
kubectl rollout status deployment/headscale -n headscale
kubectl rollout status deployment/headplane -n headscale
~~~

Back up PostgreSQL and both PVCs first. Upgrade Headscale one supported stable release at a time and read release notes for migrations.

## Client enrollment

~~~bash
kubectl exec -n headscale deploy/headscale -- headscale users create alice
kubectl exec -n headscale deploy/headscale -- headscale users list
kubectl exec -n headscale deploy/headscale -- headscale preauthkeys create --user USER_ID --expiration 24h
~~~

On a client:

~~~bash
sudo tailscale up --login-server=https://hs1.bitvividsolutions.com --authkey=PREAUTH_KEY
~~~

For interactive enrollment, omit authkey and approve the node with the Headscale CLI. Headscale documents both methods in its registration guide.

## Consuming routes from other devices

This server or node can accept routes advertised by other devices without advertising its own:

~~~bash
sudo tailscale set --accept-routes=true --accept-dns=false
tailscale status
ip route
~~~

Do not use advertise-routes on this node. Remote routes must be advertised and approved in Headscale. Avoid overlaps with the VPS, Pod CIDR, Service CIDR, or a default route.

## Troubleshooting

Headscale database or configuration:

~~~bash
kubectl logs -n headscale deploy/headscale
kubectl get configmap headscale-config -n headscale -o yaml
kubectl get events -n headscale --sort-by=.lastTimestamp
~~~

Headplane:

~~~bash
kubectl logs -n headscale deploy/headplane
kubectl get configmap headplane-config -n headscale -o yaml
~~~

Headplane dashboard is at /admin, not /. PostgreSQL no pg_hba.conf entry means the Pod CIDR is missing or SSL mode does not match. Headplane OIDC callback mismatches mean the Keycloak redirect URI and server.base_url do not match exactly.

## Recovery rules

Safe redeployment keeps the same PostgreSQL database, .env values, Secrets, headscale-data PVC, and headplane-data PVC. Run start-simple.sh again.

Do not delete the Headscale namespace or PVCs unless you intend to destroy Headscale identity and application state.
