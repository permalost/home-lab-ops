# metallb

Layer 2 load balancer that assigns IPs from a pool to `LoadBalancer`-type Services. Used on the **na** (k3s) cluster. On **orion**, this role is handled by Cilium's built-in L2 announcement feature.

## Configuration

- **Chart:** `metallb/metallb` (latest)
- **Namespace:** `metallb-system`
- **Values source:** HelmRelease inline

The IP address pool is defined in `address-pool/`. See those files for the pool range — IPs are not documented here.

## Dependencies

None for core functionality. Requires an address pool CR to be applied after the HelmRelease is ready.

## Ingress / Endpoints

No direct ingress. Assigns IPs to Services cluster-wide.

## Troubleshooting

- **Service stuck in `<pending>` external IP:** Verify the `IPAddressPool` and `L2Advertisement` CRs are applied and that the pool has available addresses.
- **ARP not responding:** Ensure MetalLB speaker pods are running on all nodes (`kubectl -n metallb-system get pods`).
