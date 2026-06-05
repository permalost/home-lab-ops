# kubernetes/infrastructure/

Shared HelmRelease and Kustomize building blocks consumed by any cluster. Each component is cluster-agnostic — cluster-specific values are injected at reconciliation time via `substituteFrom: cluster-settings`.

## Components

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| [cilium](cilium/README.md) | CNI, L2 load balancing, Gateway API, network policy | `kube-system` |
| [cert-manager](cert-manager/README.md) | TLS certificate issuance (Let's Encrypt via Cloudflare DNS) | `cert-manager` |
| [nginx](nginx/README.md) | Ingress controller (ingress-nginx) | `networking` |
| [metallb](metallb/README.md) | Layer 2 load balancer IP pool (na cluster only) | `metallb-system` |
| [vkms](vkms/README.md) | VictoriaMetrics observability stack (Grafana, vmagent, vmalert, vmsingle, Alertmanager) | `monitoring` |
| [longhorn](longhorn/README.md) | Distributed block storage | `longhorn-system` |
| [linkerd](linkerd/README.md) | Service mesh (mTLS, observability) | `linkerd` |
| [flagger](flagger/README.md) | Progressive delivery (canary deployments) | `flagger-system` |
| [democratic-csi](democratic-csi/README.md) | CSI driver for NFS/iSCSI storage | `democratic-csi` |
| [weave-gitops](weave-gitops/README.md) | Flux CD web UI | `flux-system` |

## Dependency Order

Cilium must be ready before any other component (pods can't schedule without CNI). Cert-manager should be ready before any component that needs TLS certificates. Everything else is independent.

```text
cilium → cert-manager → (everything else in parallel)
```

## Adding a Component

1. Create a new directory here with at minimum a `kustomization.yaml` and a `release.yaml` (HelmRelease) or raw manifests.
2. Add a README using the [standard template](../../docs/component-readme-template.md).
3. Wire it into a cluster by adding a Kustomization in `kubernetes/clusters/<name>/<component>.yaml`.
