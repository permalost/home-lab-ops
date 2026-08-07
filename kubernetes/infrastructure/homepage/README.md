# homepage

Link dashboard ([gethomepage/homepage](https://gethomepage.dev)) for orion —
one page linking out to every service instead of bookmarking each host.

## Configuration

- **Chart:** `homepage` from the `jameswynn/helm-charts` repo (pinned in
  `release.yaml`) — wraps the upstream `ghcr.io/gethomepage/homepage` image.
- **Namespace:** `homepage`
- **Values source:** ConfigMap (`values.yaml` via kustomize `configMapGenerator`)

Services aren't hand-listed here. `config.kubernetes.mode: cluster` +
`gateway: true` turns on live discovery of `HTTPRoute` resources cluster-wide;
each route opts in via `gethomepage.dev/*` annotations (see
`infrastructure/gateway/*-httproute.yaml` and `apps/pihole/overlays/orion`).
Add the same annotations to any new HTTPRoute to get it listed for free.

`enableRbac: true` grants the chart's own `ClusterRole` — read-only
get/list on namespaces/pods/nodes/ingresses/httproutes/gateways, nothing
that can mutate cluster state.

## Dependencies

Cilium (Gateway API) must be running. No secrets, no decryption needed.
`HOMEPAGE_ALLOWED_HOSTS` is substituted from `cluster-settings` at
reconcile time (`clusters/orion/homepage.yaml`), same as `${domain}`
elsewhere.

## Ingress / Endpoints

`homepage.${domain}` — HTTPRoute lives in `infrastructure/gateway/`
(same-namespace backend, mirrors `headlamp`).

## Access

No login — the dashboard is just outbound links plus read-only cluster
widgets, nothing sensitive to gate.
