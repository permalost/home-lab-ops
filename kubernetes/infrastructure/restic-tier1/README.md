# restic-tier1

Encrypted, deduplicated off-cluster copies of the tier-1 file data (spec
#321, GH #326): nightly in-cluster CronJobs write every tier-1 source to a
restic repo on **bignas (primary)** and a second repo on **fastnas**. The
repos land in the `tier1-critical` dataset on both boxes, next to the CNPG
barman store — restic talks plain NFS (ADR-0001), not the RustFS S3 shim.

- **This component ships only the two StorageClasses.** The per-namespace
  CronJobs, destination PVCs and the restic password secret live inside each
  app's directory (`kubernetes/apps/<app>/backup-*.yaml`,
  `restic-password.sops.yaml`) so each app's backup rides that app's own
  Flux Kustomization: unwiring an app removes its job, PVCs and secret with
  it, and no cross-app dependsOn list can rot.

## What gets copied

| Namespace | Source | How |
|---|---|---|
| forgejo | `gitea-shared-storage` | file copy (repos) |
| paperclip | `paperclip-data` | file copy — contains `master.key`, exists **only** inside the encrypted repo (ADR-0003) |
| grocy, homebox, actual-budget | `<app>-data` | file copy |
| home-automation | `mosquitto-data` + `mosquitto-conf`, `zigbee2mqtt-data`, `homeassistant-data` | three jobs — one per app pod (see "RWO" below) |
| snipe-it | `snipe-it-data` + MariaDB | `mariadb-dump` init container first; the dump (never raw DB files) is what gets stored |
| obsidian-livesync | CouchDB | API export (`_all_docs?include_docs=true&attachments=true`), never a file copy of the data dir |
| flow-collector | `flow-collector-data` | file copy |
| hermes-agents/dev/hearth/sage | instance data PVCs | file copy (state only; configs are git-managed) |

Excluded on purpose: the six CNPG clusters (covered by plugin-barman-cloud,
GH #325), tier-2 books/prints (bignas-hosted static PVs — ZFS snapshots,
GH #329), vmsingle/victorialogs/forgejo-runner (regenerable),
hermes-k8s-mcp (no PVC).

## Repo layout

Each destination PVC provisions `restic/<namespace>/<pvc-name>` under the
export (csi-driver-nfs templated `subDir`), so every job owns its repo:

```text
/mnt/storage/backups/orion/tier1-critical/restic/forgejo/forgejo-restic-bignas
/mnt/temp-storage/backups/orion/tier1-critical/restic/forgejo/forgejo-restic-fastnas
… (one pair per covered PVC group; home-automation is mosquitto-*/zigbee2mqtt-*)
```

One repo per destination PVC means a job's `restic forget --prune` never
contends with another app's lock. Each job runs `restic cat config ||
restic init` first — repos bootstrap themselves on the first scheduled run,
no manual init. Retention everywhere: `--keep-daily 14 --keep-weekly 8
--keep-monthly 6`, snapshots tagged `restic-tier1` with the app name as
`--host`.

- **Password**: one shared key in `Secret/restic-repo-password` (a
  SOPS-encrypted copy per tier-1 namespace — a SOPS MAC covers name and
  namespace, so one file cannot serve two). The plaintext recovery copy
  lives in Bitwarden (ADR-0003 flow). Rotating: decrypt one copy, change the
  value, re-encrypt, replicate to the other 13 files — existing repos keep
  working only if the same password is set everywhere at once.
- **Schedules**: staggered 05:00–09:40 America/Boise, 20 minutes apart,
  after the 02:00 ceph snapshots and clear of the 02:00–04:00 CNPG window on
  the rustfs side. `concurrencyPolicy: Forbid`, `activeDeadlineSeconds: 4h`,
  `backoffLimit: 0` — a slow first full copy delays, never overlaps, the
  next run.

## RWO sources and pod affinity

All source PVCs are RWO (rook-ceph-block): a second mount from another node
fails with Multi-Attach. Every job therefore carries **soft** pod affinity
(`preferredDuringSchedulingIgnoredDuringExecution`) to the app pod that
holds its source PVCs, so it lands on the same node and shares the attach.
Soft, not required: if the app pod is gone the volume is detached and any
node can mount it; if the app pod is stuck on a cordoned node the job fails
visibly and retries the next night. Reads are read-only and
crash-consistent — the same guarantee level as the ceph snapshots
(#323), which remain the fast in-pool rollback.

home-automation has three app pods (mosquitto, zigbee2mqtt,
homeassistant) on separate PVCs, so it gets three jobs instead of one
mount-everything job that could never satisfy three attaches.

## Restore

Both NAS boxes export the tree only to the five orion node addresses; restic
runs from any pod on those nodes (or from the NAS itself):

```bash
# list a repo (from a pod, e.g. a throwaway restic/restic:0.19.1 pod with
# the tier1-critical PVC mounted, RESTIC_PASSWORD_FILE set)
restic -r /mnt/restic-bignas snapshots --host grocy
restic -r /mnt/restic-bignas restore <id> --target /tmp/restore --include /srv/grocy-data
```

- **snipe-it DB**: `gunzip`-nothing — the stored `snipeit.sql` is plain SQL:
  `mysql snipeit < snipeit.sql` into a fresh MariaDB.
- **obsidian-livesync**: each `<db>.json` is a doc array;
  `POST {"docs": <array>, "new_edits": false}` to `/<db>/_bulk_docs` on a
  fresh database recreates the exact revisions, attachments included.
- **paperclip**: the restore triad is paperclip-db (CNPG PITR) +
  paperclip-data (restic) + the restic key (Bitwarden) — ADR-0003.

## Checking

```bash
task backup:nas-status          # landing zone + snapshot tasks (read-only)
kubectl get cronjob -A | grep restic-tier1
kubectl logs -n grocy job/restic-tier1-backup-<id>   # first run: restic init
```

Post-merge verification (Jon): `restic snapshots` lists on both NASes and a
single-file restore works. Agents never run restic against live PVCs.

## Validation

```bash
task gen:validate
task test:build
```
