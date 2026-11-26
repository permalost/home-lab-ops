# ceph-snapshots

Daily `VolumeSnapshot` of every tier-1 PVC, keeping 7 — fast in-pool rollback
(spec #321, GH #323). A plain CronJob; k8up is a restic orchestrator with no
CSI snapshot mode, so it was not a fit.

## What gets snapshotted

- **13 fixed PVCs** from the tier-1 list (spec #321 / ADR-0003), hard-coded in
  `snapshot-script.yaml` under `STATIC_PVCS`.
- **All CNPG instance PVCs**, discovered cluster-wide by the
  `cnpg.io/cluster` label. Instance names are stable across failovers, so
  per-PVC retention keeps a full history. A future CNPG cluster is picked up
  without a change here.

Deliberately excluded: `bookorbit-books` and `manyfold-libraries` (static NFS
PVs on bignas, nothing for ceph to snapshot), vmsingle/victorialogs,
forgejo-runner, and the hermes data PVCs (git-managed configs). `firefly-upload`
and `netbox-media` are ceph PVCs of tier-1 apps but are not in the spec's
tier-1 PVC list; add them to `STATIC_PVCS` if they should be covered.

Snapshots land in the ceph pool (ADR-0001): this is undo/rollback, not the
off-cluster copy. Snapshots are crash-consistent, not application-quiesced.

## How it runs

Runs at 02:00 America/Boise as `daily-tier1-snapshots` in the `ceph-snapshots`
namespace. Each run creates `daily-YYYYMMDD-<pvc>` for every PVC (UTC date in
the name) and deletes the oldest beyond 7 per PVC. One bad PVC does not fail
the run; a failed create or CNPG discovery exits 1 so the job shows as failed.

`deletionPolicy: Delete` on the VolumeSnapshotClass means deleting a
`VolumeSnapshot` object makes the snapshot-controller delete the underlying
ceph snapshot; the job touches nothing else.

## Restore (manual)

```bash
kubectl get volumesnapshot daily-20261126-grocy-data -n grocy
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grocy-data-restored
  namespace: scratch-restore
spec:
  storageClassName: rook-ceph-block
  dataSource:
    name: daily-20261126-grocy-data
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 2Gi
EOF
```

## Gotchas

- Changing `snapshot-script.yaml` updates the mounted file without restarting
  anything; the next scheduled run (and its fresh pods) picks it up.
- Snapshots are not restic: they die with the ceph pool (ADR-0001).

## Validation

```bash
task gen:validate
task test:build
```
