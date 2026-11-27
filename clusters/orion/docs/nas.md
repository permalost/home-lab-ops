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

## restic tier-1 copies (GH #326)

Nightly in-cluster CronJobs write every tier-1 file source to a restic repo
on bignas and a second repo on fastnas — plain NFS (ADR-0001), not the
RustFS S3 shim, which stays CNPG-only. Repos live in
`restic/<namespace>/<pvc-name>` subdirectories of each `tier1-critical`
export, one repo per destination PVC, provisioned by the
`nfs-restic-bignas` / `nfs-restic-fastnas` StorageClasses
(`kubernetes/infrastructure/restic-tier1/`). The CronJobs, destination PVCs
and the sops restic password live in each app's directory — the full list of
covered sources, the restore steps and the RWO-affinity design are in the
[restic-tier1 README](../../../kubernetes/infrastructure/restic-tier1/README.md).
The repo password's recovery copy is in Bitwarden (ADR-0003 flow).


## CNPG S3 endpoint (rustfs) — GH #324

CNPG cannot write backups to plain NFS (spec #321 research comment), so a
single-replica [RustFS](https://rustfs.com) S3-compatible server runs in the
cluster as the `plugin-barman-cloud` (#325) target. Manifests:
`kubernetes/apps/rustfs/` (see its README for the full contract and the
round-trip check).

- **Endpoint:** `http://rustfs.storage-system.svc:9000` — in-cluster only,
  no HTTPRoute.
- **On the NAS:** the rustfs PVC is dynamically provisioned by
  `csi-driver-nfs` (StorageClass `nfs-backups-pg`) into a `pg` **subdirectory**
  of the `tier1-critical` export → `/mnt/<pool>/backups/orion/tier1-critical/pg`
  on bignas. No separate export or dataset exists for it — the existing
  node-restricted `tier1-critical` export and its daily snapshots cover it.
- **Credentials:** `Secret/rustfs-credentials` (SOPS-encrypted in
  `kubernetes/apps/rustfs/rustfs-credentials.sops.yaml`), generated 2026-11-26
  (GH #324); rotate per the app README. The #325 `ObjectStore` references the
  same access/secret keys — each CNPG namespace holds its own SOPS copy under
  the same name (see `kubernetes/infrastructure/cnpg/README.md`).
- **Backups (GH #325):** the barman-cloud plugin (deployed in `cnpg-system`
  next to the operator) writes gzip-compressed base backups + WAL for all six
  clusters to `s3://orion-cnpg/<cluster-name>/`, with a 14-day recovery
  window and daily `ScheduledBackup`s staggered from 10:00 UTC. PITR to any
  point within that window; restores go to a scratch namespace, never in
  place.
- **Bucket:** `orion-cnpg`, created by the container entrypoint at every
  start (`rc bucket create --ignore-existing`) from
  `configmap-bootstrap.yaml`.
- **Sizing note:** the PVC requests 100Gi, but NFS datasets carry no quota —
  the effective cap is the bignas pool. ADR-0002 (sizing/credentials decisions)
  is not on disk — `docs/adr/` was never committed — so the rationale lives in
  the app README and the spec (#321) summary.

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
