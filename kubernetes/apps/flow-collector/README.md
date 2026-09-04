# flow-collector

NetFlow/IPFIX collector ([goflow2](https://github.com/netsampler/goflow2))
for the UniFi controller's NetFlow export — added to answer "what's actually
crossing VLANs" before adding inter-VLAN firewall isolation (see
`apps/external-endpoints/unifi/` and the UniFi controller's `netflow`
setting, currently `enabled: false`, `port: 2055`, `version: 10` = IPFIX).

## What it is

- `netsampler/goflow2:v2.2.6`, listening on UDP 2055, writing decoded flow
  records as JSON lines to `/data/flows.json` on an 8Gi `rook-ceph-block`
  PVC.
- Exposed via a Cilium `LoadBalancer` Service at a fixed IP
  (`10.50.0.233`, from the same `cilium/policies/ipPool.yaml` block pihole's
  DNS VIP uses) and announced over the existing UDM↔Cilium BGP session — so
  it's reachable from the UDM Pro (and any VLAN) like any other LB service,
  not just from inside the cluster.
- Set up to run indefinitely, not just for a one-off investigation — see
  Rotation below.

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
grep/jq by subnet to see what's actually crossing VLAN boundaries. Rotated
archives live alongside it as `flows-<timestamp>.json.gz`.

## Rotation

A `rotator` sidecar in the same pod (sharing the PVC — a second pod on
another node could fail to mount an RWO `rook-ceph-block` volume, so this
runs alongside `goflow2` rather than as a separate CronJob) copy-truncates
`flows.json` daily: copies it to `flows-<timestamp>.json`, gzips that copy,
truncates the live file to empty, then deletes any `.gz` archive older than
30 days. Copy-truncate rather than a signal-based reopen — goflow2 isn't
known to reopen its output on SIGHUP, but truncating a file a process
already has open is always safe, no restart needed.

8Gi with 30-day gzip retention is comfortable headroom for a home network's
flow volume; revisit the size or retention window if that assumption stops
holding (e.g. NetFlow gets pointed at something much busier later).
