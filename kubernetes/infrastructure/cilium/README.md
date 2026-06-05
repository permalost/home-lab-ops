# cilium

CNI for both clusters, providing pod networking, L2 load balancer announcements (replacing MetalLB on orion), Gateway API, Hubble observability, and network policy enforcement.

## Configuration

- **Chart:** `cilium/cilium` (>=1.16.0)
- **Namespace:** `cilium` (HelmRelease targets the `cilium` namespace; Cilium then manages pod networking cluster-wide including `kube-system`)
- **Values source:** ConfigMap (`values.yaml` via kustomize `configMapGenerator`)

Key non-default choices:
- `kubeProxyReplacement: true` — Talos has no kube-proxy; Cilium must replace it entirely
- `k8sServiceHost` / `k8sServicePort` — explicitly set for Talos (no in-cluster DNS at bootstrap time)
- L2 announcements enabled — Cilium serves the LoadBalancer IP pool directly (see `policies/ipPool.yaml` for the pool range) without MetalLB on orion
- `SYS_MODULE` capability removed — required for Talos which does not allow kernel module loading from pods

## Dependencies

Must be the first component applied. No other pods will schedule until Cilium is ready.

## Ingress / Endpoints

Hubble UI is available in-cluster. Gateway API gateway can be created from `policies/`.

## Troubleshooting

- **Pods stuck in `ContainerCreating`:** Cilium is not yet ready. Check `kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium`.
- **L2 announcements not working:** Check `CiliumL2AnnouncementPolicy` and `CiliumLoadBalancerIPPool` CRs in `policies/`.
- **`kubeProxyReplacement` errors on Talos:** Ensure the Talos machineconfig has `network.kubespan` disabled and the correct `apiServerAddress`.
