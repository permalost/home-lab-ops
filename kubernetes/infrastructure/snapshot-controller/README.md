# snapshot-controller

Deploys the CSI [snapshot-controller](https://github.com/kubernetes-csi/external-snapshotter)
(CRDs + control loop) so `VolumeSnapshot` objects actually reach `ReadyToUse`.
The cluster already runs the `csi-snapshotter` sidecar in the rook-ceph
ctrlplugin; only the controller and CRDs were missing.

- Namespace: `kube-system` (upstream default), 2 replicas with leader election.
- Image: `registry.k8s.io/sig-storage/snapshot-controller:v8.7.1`, pinned by digest.
- Group snapshot CRDs are not installed; nothing here uses them.

The `VolumeSnapshotClass` for the RBD driver lives in
[rook-ceph-cluster](../rook-ceph-cluster/) and the daily snapshot job in
[ceph-snapshots](../ceph-snapshots/).

## Dependencies

Cluster-level only: the CRDs and controller have no dependency on rook. The
`rook-ceph-cluster` Kustomization waits for this one so its
`VolumeSnapshotClass` applies after the CRDs exist.

## Validation

```bash
task gen:validate
```
