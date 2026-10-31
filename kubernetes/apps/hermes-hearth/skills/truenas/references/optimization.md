# TrueNAS thresholds and tuning

Each item: the threshold, the advice, and the cost of following it. Say the
cost in the report.

## Both NASes

| Check | Warn | Act | Notes |
|---|---|---|---|
| Pool used | 80% | 90% | ZFS slows and fragments as it fills; cannot be undone by deleting later |
| Last scrub | > 35 days | > 60 days | Scrub finds silent corruption; costs hours of extra disk load |
| Scrub errors | any repaired | any unrecoverable | Unrecoverable: stop writes, tell Jon |
| Alerts | any WARNING | any CRITICAL | |
| Snapshot age | newest > 2x task interval | task failing | Missing snapshots are silent until you need one |
| ARC hit ratio | < 90% | < 80% | Low means more RAM or a smaller working set, not a tunable |
| Boot pool | any error | degraded | |

Compression: keep `lz4` (default) or `zstd` on all datasets; turn it off
only for already-compressed data, and the gain is small. `atime=off` on
datasets without a need for access times saves writes. Snapshot retention:
many hourly snapshots of a churning dataset hold deleted data; cut the
count before adding disks.

## fastnas (SSD)

- Trim: autotrim on the pool, or a monthly manual trim. Cost: brief extra IO.
- SMART: SHORT test weekly, LONG test quarterly; watch `Percentage Used`
  and media errors, not reallocated sectors.
- Temperatures: warn 60 C, act 70 C.
- Pool near full hurts SSD write speed and wear more than HDD; keep under 80%.
- Sync-write latency: a SLOG is not needed on an all-SSD pool.

## bignas (HDD)

- Scrub monthly, not weekly: a scrub reads every block, and on large HDD
  pools it runs for a day or more.
- SMART: SHORT test weekly, LONG test monthly, staggered so no two disks
  test at once. Any nonzero `Reallocated_Sector_Ct`, `Current_Pending_Sector`
  or `Offline_Uncorrectable` that is rising: plan a replacement now.
  `UDMA_CRC_Error_Count` rising means a cable, not the disk.
- Temperatures: warn 45 C, act 50 C. Sustained heat shortens drive life.
  Fix airflow before touching settings.
- Spin-down: saves power and wear only if the pool is idle for hours; each
  spin-up is a few seconds of delay and a bit of wear. Do not enable on
  pools with periodic jobs (snapshots, replication, apps) under an hour apart.
- Media datasets: `recordsize=1M` helps large sequential files; it hurts
  small random writes. Changing it affects new writes only.
- SLOG, L2ARC, special vdev: add only for a measured problem (sync-write
  heavy NFS, a working set larger than RAM, huge metadata). They add cost
  and failure points; a special vdev loss loses the pool.
- RAIDZ width: wider means more usable space and a longer resilver while
  a second disk can fail. Past about 8 wide on large disks, prefer RAIDZ2 or more vdevs.
- SMR drives: very slow resilver and sustained writes. Check the model
  against the vendor's SMR list before replacing a disk.
- Resilver and scrub both slow the pool; do not start a second one.
