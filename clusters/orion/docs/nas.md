# NAS shares on orion (bignas)

How the bignas NFS stores reach cluster workloads. The mounts are **static**:
each share has one `PersistentVolume` pointing at the existing data — nothing
is provisioned behind your back. `csi-driver-nfs` (see
`kubernetes/infrastructure/csi-driver-nfs/README.md`) is installed for future
dynamic provisioning only.

## Shares

| Share (NAS dataset) | NFS export path | PersistentVolume | PVC |
|---------------------|-----------------|------------------|-----|
| `storage/books`     | `/mnt/storage/books` | `nas-books`   | created by the consuming app (BookOrbit, WDO-157) |
| `storage/prints`    | `/mnt/storage/prints` | `nas-prints`  | created by the consuming app (Manyfold, WDO-162) |
| `storage/photos`    | `/mnt/storage/photos` | `nas-photos`  | unclaimed — first consumer binds it |

A `PersistentVolumeClaim` is namespaced, so each app adds its own PVC in its
own namespace and binds the static PV by name (`volumeName: nas-books`,
`storageClassName: ""`). The contract — with a copy-paste PVC example — lives
in `kubernetes/infrastructure/nas-storage/README.md`.

## Access and credentials

- The NFS server address is `${nasNfsIp}`, a Flux substitution variable stored
  SOPS-encrypted in `Secret/nas-nfs-secrets`
  (`kubernetes/settings/orion/nas-nfs.sops.yaml`) — never in plain YAML; this
  is a public repo.
- The exports are open to any host with **no squash**, by decision (WDO-168,
  2026-11: temporary). Pods must not rely on squash: any workload mounting
  these PVs sets its UID/GID explicitly (`securityContext.runAsUser` /
  `runAsGroup`, or `fsGroup`) so files on the NAS get a stable owner.
- `persistentVolumeReclaimPolicy: Retain` — deleting a PVC never touches NAS
  data.

## Troubleshooting

| Symptom | Likely cause | Check or fix |
|---|---|---|
| Pod stuck in `ContainerCreating`, mount error | NFS service is off, the export network is wrong, or the NAS is down | TrueNAS NFS service status, the share's allowed networks, `showmount -e` from a debug pod |
| `Permission denied` when writing | Mapall is not set, or the owner isn't 3000 | Share mapall, dataset owner |
| `Stale file handle` after a NAS reboot | Mount held across the restart | Restart the pod |
| Web UI 502 | Wrong address or port in the endpoint | EndpointSlice, NAS reachability |
| Pool degraded or SMART errors | Disk failing | TrueNAS alert, then Jon replaces the disk |

Agents run read-only checks (pod events, `kubectl describe`) and report. Fixes
on the NAS are Jon's. Fixes on orion go through PRs.
