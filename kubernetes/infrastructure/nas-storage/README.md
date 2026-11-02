# nas-storage — static NFS PVs for the bignas stores

Cluster-scoped `PersistentVolume`s that expose the bignas NFS exports to orion.
App workloads bind to them with a namespaced PVC (see "Binding" below); the PVs
themselves carry no workload.

## Shares

| PV name | NAS dataset | NFS export path | Server |
|---------|-------------|-----------------|--------|
| `nas-books` | `storage/books` | `/mnt/storage/books` | `${nasNfsIp}` |
| `nas-prints` | `storage/prints` | `/mnt/storage/prints` | `${nasNfsIp}` |
| `nas-photos` | `storage/photos` | `/mnt/storage/photos` | `${nasNfsIp}` |

`${nasNfsIp}` comes from `kubernetes/settings/orion/cluster-settings.yaml`.
The server also serves the same datasets over SMB for desktop access.

## Binding (for app manifests)

These PVs are static: bind a workload to one by name, not by storage class.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: books
  namespace: <app-namespace>
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""       # required: keeps dynamic provisioners out of the way
  volumeName: nas-books      # bind to the static PV by name
  resources:
    requests:
      storage: 50Gi          # must be <= the PV capacity (1Ti)
```

Then mount the PVC on the Deployment like any other volume. A PVC bound this
way is exclusive to that app; if two apps need the same NAS dataset, add one
PV/PVC pair per consumer instead of sharing (the NAS export is the same, only
the PV object differs).

## Posture

- The NFS exports are open to any host **by decision** (WDO-194/WDO-168,
  2026-11-02): no export network restriction and no squash, so pods read and
  write with their own UID/GID. Set the workload's `fsGroup`/run-as UID to
  match what should own files on the NAS.
- The same datasets are available via SMB (auth-based) for desktop clients.
- `persistentVolumeReclaimPolicy: Retain` — deleting a PVC never touches the
  NAS data.
