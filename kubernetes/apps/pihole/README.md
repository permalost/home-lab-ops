# pihole

DNS + ad-blocking, built on `webapp/base` + `webapp/components/*`.

## Layout

- `base/` — Deployment/Service, `configMap.yaml` + `env/`, `secret.yaml` (SOPS), patches for env/volumes/ports.
- `overlays/orion/` — **wired into orion** (`kubernetes/clusters/orion/pihole.yaml`). Namespace `pihole`, `httproute`, DNS via `loadbalancer.yaml` (Cilium LB-IPAM, 53 UDP+TCP).
- `overlays/na/` — unused, kept from decommissioned na (used `ingress` instead of `httproute`).

## Config

- Env overrides: `base/env`. Admin creds: `base/secret.yaml` (SOPS, → Secret `pihole-admin`).
- Cluster vars via `substituteFrom: cluster-settings` + literal `appName: pihole, subdomain: dns`.

## Troubleshooting

- **DNS not resolving:** check `dns` Service got an IP from Cilium LB-IPAM, and `io.cilium/lb-ipam-ips` matches `${externalDnsIp}`.
- **Config not applying:** `configMapGenerator` hashes the ConfigMap name — a stale Pod may lag until Flux reconciles.
