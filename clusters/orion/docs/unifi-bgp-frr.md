# UniFi UDM BGP / FRR config

This is the FRR config to upload in **UniFi → Settings → Routing → BGP**.

Cluster ASN: `65001`
UDM ASN: `65000`
Peers: all five orion nodes on VLAN 50 (`10.50.0.11–13` control plane, `10.50.0.21–22` workers)

```
router bgp 65000
  bgp router-id 10.50.0.1
  neighbor 10.50.0.11 remote-as 65001
  neighbor 10.50.0.12 remote-as 65001
  neighbor 10.50.0.13 remote-as 65001
  neighbor 10.50.0.21 remote-as 65001
  neighbor 10.50.0.22 remote-as 65001
  address-family ipv4 unicast
    neighbor 10.50.0.11 activate
    neighbor 10.50.0.12 activate
    neighbor 10.50.0.13 activate
    neighbor 10.50.0.21 activate
    neighbor 10.50.0.22 activate
  exit-address-family
```

## After applying

Verify sessions are up from the UDM:

```
vtysh -c "show bgp summary"
```

All five neighbors should show `Establ` state and a non-zero `PfxRcd` (received
prefixes) — expect at least two: `10.50.0.231/32` (gateway) and `10.50.0.232/32`
(pihole DNS).

```
vtysh -c "show ip route bgp"
```

Both VIPs should appear as BGP routes.

## Verify from cluster (read-only)

```
kubectl --context admin@orion -n kube-system exec ds/cilium -- cilium bgp peers
kubectl --context admin@orion -n kube-system exec ds/cilium -- cilium bgp routes advertised ipv4 unicast
```
