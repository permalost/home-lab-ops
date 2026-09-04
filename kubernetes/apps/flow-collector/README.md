# flow-collector

NetFlow/IPFIX collector ([goflow2](https://github.com/netsampler/goflow2))
for the UniFi controller's NetFlow export — added to answer "what's actually
crossing VLANs" before adding inter-VLAN firewall isolation (see
`apps/external-endpoints/unifi/` and the UniFi controller's `netflow`
setting, currently `enabled: false`, `port: 2055`, `version: 10` = IPFIX).

## What it is

- `netsampler/goflow2:v2.2.6`, listening on UDP 2055, writing decoded flow
  records as JSON lines to `/data/flows.json` on a 4Gi `rook-ceph-block` PVC.
- Exposed via a Cilium `LoadBalancer` Service at a fixed IP
  (`10.50.0.233`, from the same `cilium/policies/ipPool.yaml` block pihole's
  DNS VIP uses) and announced over the existing UDM↔Cilium BGP session — so
  it's reachable from the UDM Pro (and any VLAN) like any other LB service,
  not just from inside the cluster.

## Wiring up NetFlow export on the controller

Not done by this PR — the collector needs to exist and have its IP before
pointing the controller at it. Once this is merged and the Service has an
IP: Settings → System → NetFlow (or `PUT` the `netflow` setting object via
the Network API) → enable, collector `10.50.0.233:2055`, version IPFIX.

## Reading the data

```bash
kubectl exec -n flow-collector deploy/flow-collector-deploy -- tail -f /data/flows.json
```

Each line is one flow record (`SrcAddr`/`DstAddr`, ports, bytes, etc.) —
grep/jq by subnet to see what's actually crossing VLAN boundaries.

## This is a temporary investigative tool, not permanent monitoring

Nothing rotates `flows.json` — it grows unbounded on a home network's
traffic volume. Fine for a data-gathering window before deciding on
isolation rules; if this stays running long-term, it needs log rotation or
a real time-series backend instead of appending to one file forever.
