# pihole

DNS + ad-blocking. Built on `apps/webapp/base` + `apps/webapp/components/*`,
with pihole-specific patches layered on top.

This directory was renamed from `pihole2` — it was originally a second
generation of pihole running alongside a legacy `apps/pihole` (flat
manifests, no webapp base), both on the decommissioned `na` cluster. The
legacy version is gone; this is now the only pihole in the repo.

## Layout

- `base/` — Deployment/Service via `webapp/base`, `configMap.yaml` +
  `env/` (via `configMapGenerator`), `secret.yaml` (SOPS-encrypted), and
  patches under `patches/` for env vars, volumes, and port overrides.
- `overlays/orion/` — **wired into the orion cluster**
  (`kubernetes/clusters/orion/pihole.yaml`, Kustomization CR named `pihole`).
  Namespace `pihole`, routed via the `httproute` component (Gateway API),
  DNS exposed through `loadbalancer.yaml` (Cilium LB-IPAM, ports 53 UDP+TCP).
- `overlays/na/` — **not wired into any cluster.** Kept from the
  decommissioned `na` cluster pending possible migration; used the `ingress`
  component (nginx) instead of `httproute`, since na had no Gateway API.

## Configuration

- Environment overrides in `base/env` (consumed via `configMapGenerator`).
- Admin credentials in `base/secret.yaml` (SOPS-encrypted, namePrefix
  `pihole-` → Secret `pihole-admin`).
- Cluster-wide variables (`${domain}`, etc.) substituted via
  `postBuild.substituteFrom: cluster-settings` on the Kustomization CR, plus
  literal `postBuild.substitute: {appName: pihole, subdomain: dns}`.

## Troubleshooting

- **DNS not resolving:** check the `dns` LoadBalancer Service got an IP from
  Cilium's LB-IPAM (`kubectl get svc dns -n pihole`), and that
  `io.cilium/lb-ipam-ips` matches `${externalDnsIp}` in orion's
  `cluster-settings` ConfigMap.
- **Config changes not applying:** confirm `env/` or `secret.yaml` changes
  were picked up — `configMapGenerator` content-hashes the ConfigMap name,
  so a stale Pod may still reference the old generated name until Flux
  reconciles.
