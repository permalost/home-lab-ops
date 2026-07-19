# UniFi UDM BGP / FRR config

This is the FRR config to upload in **UniFi → Settings → Routing → BGP**.

Cluster ASN: `65001`
UDM ASN: `65000`
Peers: all five orion nodes on VLAN 50 (`10.50.0.11–13` control plane, `10.50.0.21–22` workers)
LB pool: `10.50.0.230–239` (CiliumLoadBalancerIPPool `pool`, fits within `10.50.0.224/28`)

## FRR config

FRR enforces RFC 8212 (`bgp ebgp-requires-policy`) by default — eBGP routes from
a neighbor with no inbound policy are silently rejected (sessions still establish,
but `PfxRcd` shows `(Policy)`). The config below adds a prefix-list scoped to the
LB pool and a route-map applied inbound on all neighbors.

```
ip prefix-list CILIUM-LB seq 5 permit 10.50.0.224/28 le 32

route-map CILIUM-IN permit 10
 match ip address prefix-list CILIUM-LB

router bgp 65000
 bgp router-id 10.50.0.1
 neighbor 10.50.0.11 remote-as 65001
 neighbor 10.50.0.12 remote-as 65001
 neighbor 10.50.0.13 remote-as 65001
 neighbor 10.50.0.21 remote-as 65001
 neighbor 10.50.0.22 remote-as 65001
 address-family ipv4 unicast
  neighbor 10.50.0.11 activate
  neighbor 10.50.0.11 route-map CILIUM-IN in
  neighbor 10.50.0.12 activate
  neighbor 10.50.0.12 route-map CILIUM-IN in
  neighbor 10.50.0.13 activate
  neighbor 10.50.0.13 route-map CILIUM-IN in
  neighbor 10.50.0.21 activate
  neighbor 10.50.0.21 route-map CILIUM-IN in
  neighbor 10.50.0.22 activate
  neighbor 10.50.0.22 route-map CILIUM-IN in
 exit-address-family
```

## After applying

Verify sessions are up and routes are being received (requires SSH access or
UniFi console):

```
vtysh -c "show bgp summary"
```

All five neighbors should show `Establ` state and `PfxRcd` of **3** (not
`(Policy)`): `10.50.0.230/32` (cilium-ingress), `10.50.0.231/32` (gateway),
`10.50.0.232/32` (pihole DNS).

```
vtysh -c "show ip route bgp"
```

All three VIPs should appear as BGP routes with next-hops pointing to the
advertising node IPs.

## Verify from cluster (read-only)

```bash
KUBECONFIG=~/.kube/orion.yaml kubectl -n cilium exec ds/cilium -c cilium-agent -- \
  cilium bgp peers

KUBECONFIG=~/.kube/orion.yaml kubectl -n cilium exec ds/cilium -c cilium-agent -- \
  cilium bgp routes advertised ipv4 unicast
```

## Notes

- Once BGP routes are installed, the UDM will prefer the /32 BGP routes (longest
  prefix match) over the connected /24, making L2 ARP announcements a fallback
  rather than the only path. This removes the dependency on L2 for cross-VLAN
  routing to LB VIPs.
- The FRR config is uploaded via the UniFi UI and is not git-managed. Keep this
  doc in sync with any changes made there.
