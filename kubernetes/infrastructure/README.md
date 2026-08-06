# kubernetes/infrastructure/

Shared HelmRelease and Kustomize building blocks consumed by any cluster. Each component is cluster-agnostic — cluster-specific values are injected at reconciliation time via `substituteFrom: cluster-settings`.

## Components

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| [cilium](cilium/README.md) | CNI, L2 load balancing, Gateway API, network policy | `kube-system` |
| [cert-manager](cert-manager/README.md) | TLS certificate issuance (Let's Encrypt via Cloudflare DNS) | `cert-manager` |
| [vkms](vkms/README.md) | VictoriaMetrics observability stack (Grafana, vmagent, vmalert, vmsingle, Alertmanager) | `monitoring` |
| rook-ceph-operator | Ceph operator | `rook-ceph` |
| rook-ceph-cluster | Ceph cluster (default block storage) | `rook-ceph` |
| gateway-api | Gateway API CRDs | `gateway-system` |
| gateway | Gateway + HTTPRoutes, wildcard TLS | `gateway` |
| external-dns | DNS record automation | `external-dns` |
| coredns | Cluster DNS patch | `kube-system` |
| rbac | Cluster RBAC | — |
| [weave-gitops](weave-gitops/README.md) | Flux CD web UI (na-only, pending migration to orion) | `flux-system` |
| [flagger](flagger/README.md) | Progressive delivery (canary deployments) — currently unreferenced by any cluster | `flagger-system` |

*(Components without a linked README don't have one yet — tracked for the docs cleanup pass.)*

## Dependency Order

Cilium must be ready before any other component (pods can't schedule without CNI). Cert-manager should be ready before any component that needs TLS certificates. Everything else is independent.

```text
cilium → cert-manager → (everything else in parallel)
```

## Adding a Component

1. Create a new directory here with at minimum a `kustomization.yaml` and a `release.yaml` (HelmRelease) or raw manifests.
2. Add a README documenting purpose, dependencies, and any required `postBuild.substitute` variables.
3. Wire it into a cluster by adding a Kustomization in `kubernetes/clusters/<name>/<component>.yaml`.

**Canonical pattern for Helm components with a values file:** follow `cilium/` — use a `configMapGenerator` in `kustomization.yaml` to generate a ConfigMap from `values.yaml`, add `valuesFrom` in the HelmRelease pointing to that ConfigMap, and include a `kustomizeconfig.yaml` with a `nameReference` so that changing `values.yaml` automatically triggers a HelmRelease re-reconciliation.
