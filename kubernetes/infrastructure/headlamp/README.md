# headlamp

General-purpose cluster dashboard (workloads, CRDs, logs, exec) for orion.

## Configuration

- **Chart:** `headlamp-k8s/headlamp` (pinned in `release.yaml`)
- **Namespace:** `headlamp`
- **Values source:** ConfigMap (`values.yaml` via kustomize `configMapGenerator`)

`clusterRoleBinding.clusterRoleName` is set to the built-in `view` role
(chart default is `cluster-admin`) — dashboard is browse-only, matching the
"changes go through git+Flux" convention for this repo.

## Dependencies

Cilium (Gateway API) must be running. No secrets, no decryption needed.

## Ingress / Endpoints

`headlamp.${domain}` — HTTPRoute lives in `infrastructure/gateway/`
(same-namespace backend, like `hubble-ui`; see that dir's README/traps).

## Access

Login is token-based (chart default), not auto-authenticated. Mint a token
for the dashboard's own service account:

```bash
kubectl -n headlamp create token headlamp
```

Paste it into the Headlamp login screen. Token TTL follows `--duration`
(default 1h); `config.sessionTTL` in `values.yaml` caps the UI session at 24h.
