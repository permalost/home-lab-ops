# cilium

CNI for the orion cluster, providing pod networking, kube-proxy replacement, L2 load balancer announcements, Gateway API, Hubble observability, and network policy enforcement.

## Bootstrap (before Flux)

Talos sets `cni.name: none` so the cluster starts with no CNI. Pods (including Flux itself) cannot schedule until Cilium is running. This creates a chicken-and-egg problem: Flux can't install Cilium if Cilium isn't already there.

**Solution:** install Cilium manually into `kube-system` once before bootstrapping Flux. This is the only manual Helm operation in the cluster lifecycle.

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.18.4 \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set gatewayAPI.enabled=true \
  --set gatewayAPI.enableAlpn=true \
  --set gatewayAPI.enableAppProtocol=true \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
```

Wait for Cilium to report Ready before proceeding to Flux bootstrap:

```bash
kubectl -n kube-system rollout status daemonset/cilium
```

## Flux-managed install (cilium namespace)

Once Flux is bootstrapped, it takes over Cilium management and installs it into the `cilium` namespace (see `release.yaml`). This includes additional features not needed for bare CNI: L2 announcements, ExternalIPs, the Cilium ingress controller, and TLS secret management.

The `kube-system` bootstrap install must be removed before the Flux-managed install can become healthy. Both cannot run simultaneously — they share eBPF kernel maps and `cilium-envoy` hostPorts.

### Migrating from kube-system to cilium namespace

Run these steps during a maintenance window. There will be a brief CNI gap (seconds to ~1 minute) between removing the old install and the new DaemonSet becoming Ready.

```bash
# 1. Prevent Flux from fighting with the migration mid-flight
flux suspend kustomization cilium -n flux-system

# 2. Remove the bootstrap install
helm uninstall cilium -n kube-system

# 3. Wait for kube-system cilium pods to terminate
kubectl -n kube-system get pods -l k8s-app=cilium -w

# 4. Hand control back to Flux — it will install into the cilium namespace
flux resume kustomization cilium -n flux-system

# 5. Monitor
kubectl get pods -n cilium -w
flux get helmrelease cilium -n cilium -w
```

If the HelmRelease had previously exhausted its retry budget (3 retries), force a fresh reconcile:

```bash
flux reconcile helmrelease cilium -n cilium --reset
```

## Configuration

- **Chart:** `cilium/cilium` (`>=1.16.0`)
- **Namespace:** `cilium` (Flux-managed); initial bootstrap targets `kube-system`
- **Values source:** ConfigMap generated from `values.yaml` via kustomize `configMapGenerator`

Key non-default choices:

| Setting | Value | Reason |
|---|---|---|
| `kubeProxyReplacement` | `true` | Talos has no kube-proxy; Cilium must replace it entirely |
| `k8sServiceHost` / `k8sServicePort` | `localhost:7445` | Talos local API proxy; no in-cluster DNS at bootstrap time |
| `cgroup.autoMount.enabled` | `false` | Talos mounts cgroups itself; Cilium must not remount |
| `cgroup.hostRoot` | `/sys/fs/cgroup` | Talos cgroup v2 mount path |
| `l2announcements.enabled` | `true` | Replaces MetalLB for LoadBalancer IP announcement on orion |
| `tls.secretsNamespace.name` | `cilium` | TLS secrets for Gateway API placed in the Cilium namespace |
| `operator.replicas` | `1` | Sufficient for a five-node homelab |
| `SYS_MODULE` omitted | — | Talos does not allow kernel module loading from pods |

## Dependencies

Must be the first component applied — no pods will schedule until Cilium removes the `node.cilium.io/agent-not-ready` taint it sets via `patches/cluster/30-cilium-prep.yaml`.

Gateway API CRDs must be installed for `gatewayAPI.enabled: true` to work. The `gateway` Kustomization depends on Cilium, not the other way around.

## Ingress / Endpoints

- **Hubble UI:** routed via Gateway API HTTPRoute at `hubble.${domain}` (see `hubble-httproute.yaml`)
- **LoadBalancer pool:** `10.50.0.230–10.50.0.239` (see `policies/ipPool.yaml`)
- **L2 announcement interface:** `enp[12]s0.50` (VLAN 50 trunk interface pattern)

## Troubleshooting

**`cilium-envoy` pods Pending / `didn't have free ports`:**
Another Cilium instance (typically the `kube-system` bootstrap) is holding `hostPort: 9964`. Remove the old install first; see Migration above.

**Pods stuck in `ContainerCreating`:**
Cilium agent is not yet Ready. Check `kubectl -n cilium get pods -l k8s-app=cilium`.

**L2 announcements not working:**
Verify `CiliumL2AnnouncementPolicy` and `CiliumLoadBalancerIPPool` CRs are present and that the interface regex in `policies/l2-policy.yaml` matches the node's VLAN 50 NIC name.

**`kubeProxyReplacement` errors on Talos:**
Ensure `network.kubespan` is disabled in the Talos machineconfig and the kubelet is not also running kube-proxy.

**HelmRelease retry budget exhausted:**
```bash
flux reconcile helmrelease cilium -n cilium --reset
```
