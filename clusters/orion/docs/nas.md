# NAS shares on orion (bignas)

How the bignas NFS stores reach cluster workloads. The mounts are **static**:
each share has one `PersistentVolume` pointing at the existing data — nothing
is provisioned behind your back. `csi-driver-nfs` (see
`kubernetes/infrastructure/csi-driver-nfs/README.md`) is installed for future
dynamic provisioning only.

## Shares

| Share (NAS dataset) | NFS export path | PersistentVolume | PVC |
|---------------------|-----------------|------------------|-----|
| `storage/books`     | `/mnt/storage/books` | `nas-books`  | `bookorbit-books` (BookOrbit, WDO-157) |
| `storage/prints`    | `/mnt/storage/prints` | `nas-prints`  | `manyfold-libraries` (Manyfold, WDO-162) |
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

## Backup landing zone (both NASes)

Orion backups (spec: restic copies, the CNPG S3 shim, tier-2 source snapshots)
land in a dedicated dataset tree on **both** boxes: bignas is the primary
target, fastnas holds the tier-1 second copies. Tier-2 bulk data is copied to
bignas only, but the matching dataset, export and snapshot task exist on
fastnas too so the layout is identical.

| Dataset (tree) | NFS export path | Purpose |
|---|---|---|
| `backups/orion/tier1-critical` | `/mnt/<pool>/backups/orion/tier1-critical` | restic tier-1 repos, CNPG barman store |
| `backups/orion/tier2-bulk` | `/mnt/<pool>/backups/orion/tier2-bulk` | restic tier-2 repo (bignas) |

The tree sits under each box's data pool (`storage` on bignas,
`temp-storage` on fastnas), so full dataset names are
`storage/backups/orion/…` and `temp-storage/backups/orion/…`.

- **Exports** are restricted to the five orion node addresses on VLAN 50
  (per-node entries; the list lives in `NODES.md`) — unlike the existing
  stores above, they are never open to the LAN.
- **Snapshots**: one recursive daily ZFS snapshot task per box on the
  `backups/orion` tree, keep 14 days — a deletion bug inside the cluster
  cannot destroy the restic repos themselves.
- **Creation**: the `agent-maint` NAS user is read-only on purpose, so the
  datasets, exports and snapshot task are created by Jon in the TrueNAS UI.
- **Preflight gate**: no backup writes until bignas is verified healthy.
  Recorded 2026-11-26 after the `sdf` replacement: pool `storage` ONLINE and
  healthy, resilver finished with 0 errors, no active alerts. The
  `smart.test.results` API call is broken on TrueNAS 25.04.2.6 (EINVAL on its
  own schema), so SMART state is evidenced by the alert list and the weekly
  SHORT test schedule instead.

## Checking the landing zone

`task backup:nas-status` queries both NASes read-only and reports datasets,
exports, snapshot tasks, pool health and alerts at a glance. It exits 0 only
when every expected piece is in place on both reachable boxes.

Credentials are read from the environment (`TRUENAS_BIGNAS_URL`,
`TRUENAS_BIGNAS_API_KEY`, and the `FASTNAS` pair — the same names as
`Secret/hermes-secrets`); keep them in `.config.env`, never in git. The
script needs the `websockets` python package (`pip install --user websockets`
or `uv run scripts/backup-nas-status.py`).

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
