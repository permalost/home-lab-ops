---
name: truenas
description: "Check, troubleshoot and tune the two TrueNAS boxes: fastnas (SSD) and bignas (HDD). Pool health, capacity, scrubs, SMART, disk temps, alerts, snapshots, replication, ARC, updates. Read-only except one action: it can create an agent- snapshot."
version: 0.1.0
author: community
license: MIT
platforms: [linux, macos]
prerequisites:
  env_vars: [FASTNAS_URL, FASTNAS_API_KEY, BIGNAS_URL, BIGNAS_API_KEY]
  commands: [python3]
metadata:
  hermes:
    tags: [TrueNAS, ZFS, Storage, NAS, SMART, Maintenance]
    homepage: https://www.truenas.com
    related_skills: []
---

# TrueNAS

Two NASes, one skill:

| Name | Media | Version | Cares most about |
|---|---|---|---|
| `fastnas` | SSD | 25.10 | capacity, trim, snapshot growth, latency |
| `bignas` | HDD | 25.04 | disk health, temperatures, scrub/resilver time, spin-down |

"fast"/"SSD" means fastnas. "big"/"HDD"/"spinning" means bignas. If the
request names neither, check both and report them separately.

## What you may change

One action: create a snapshot named `agent-<YYYYMMDD-HHMM>`
(`pool.snapshot.create` on fastnas, `zfs.snapshot.create` on bignas).
Everything else is read-only. Never delete or roll back a snapshot, start a
scrub or SMART test, edit pool/dataset/share/network/snapshot-task settings,
apply updates, reboot, or offline a disk.

When a scrub or SMART test is overdue, say so and name where Jon starts it
(below). Starting them needs roles the agent does not have, on purpose:
scrub needs `POOL_WRITE` (pool management), and SMART tests are admin-only
on bignas and not in the API on fastnas.

`scripts/tn.py` refuses any other write, and the NAS user `agent-maint`
has no wider role. If either fence blocks you, stop and say so.

## Use the helper

All calls go through `scripts/tn.py` (JSON-RPC over WebSocket, same on both
versions). Run `python3 scripts/tn.py ...` from this skill's directory; if
`websockets` is missing, `pip install --user websockets` first (`uv run` also works).

```bash
python3 scripts/tn.py bignas pool.query
python3 scripts/tn.py bignas smart.test.results
python3 scripts/tn.py fastnas --methods snapshot   # find a renamed method
```

Why not curl: fastnas (25.10) dropped REST for update checks and
`zfs.snapshot`, and removed SMART from the API. See `references/api.md`. Keys must travel over HTTPS only;
TrueNAS revokes a key used over plain HTTP, and the helper refuses `http://`.

## Procedure: health check

Do this per NAS, cheapest first. Stop and report as soon as something
explains the complaint.

1. `alert.list` — anything not dismissed? These are the NAS's own findings.
2. `pool.query` — `status` is `ONLINE`, `healthy` true, no errors in
   `topology`, `scan` shows last scrub and its errors.
3. Capacity: `size`/`allocated` -> warn at 80% used, act at 90%.
4. `disk.query` + `disk.temperatures` — temps (limits in `references/optimization.md`).
5. SMART. bignas: `smart.test.results` — any FAILED, or no test in 35 days.
   fastnas: 25.10 has no SMART in the API; rely on `alert.list` and say so.
   Raw attributes (reallocated, pending, CRC) are not readable with this
   role; if a disk looks suspect, ask Jon to read them in the UI or shell.
6. `pool.snapshottask.query` + `pool.snapshot.query` (fastnas) /
   `zfs.snapshot.query` (bignas) — newest snapshot older than its task
   interval means the task is failing.
7. `replication.query`, `cloudsync.query` — `job.state` FAILED?
8. Updates: `update.status` (fastnas) / `update.check_available` (bignas).
9. `boot.get_state` — boot pool healthy.

If all clean, say so in two lines. Do not keep digging.

Overdue items go in the report as a task for Jon:
- Scrub (last scrub older than the limit in `references/optimization.md`):
  Data Protection > Scrub Tasks, or Storage > pool > Scrub.
- SMART test on bignas: Data Protection > Periodic S.M.A.R.T. Tests.
- SMART test on fastnas: 25.10 removed the scheduler; the old schedule became
  a Cron Job (System > Advanced > Cron Jobs) that calls `disk.smart_test`.
  If it is missing, tell Jon.

## Procedure: one symptom

| Symptom | Look at |
|---|---|
| Slow reads/writes | `pool.query` scan (scrub/resilver running?), `reporting.get_data` ARC and disk busy, temps (HDD thermal throttle), pool > 80% full |
| Alert emailed | `alert.list`, then the object it names |
| Disk "degraded" | `pool.query` topology, `alert.list`, `smart.test.results` (bignas) |
| Pool filling | `pool.dataset.query` sorted by `used`, `snapshot_count`; snapshots are the usual cause |
| Share unreachable | `service.query` (smb/nfs running?), `alert.list`; if the NAS answers here, the problem is network or share config, not the pool |

## Report

Write it for the person who owns the NAS. Per issue: what is wrong in plain
words (not the raw field), the specific action, and its side effects. A
scrub slows the pool for hours; a LONG test on an HDD adds load for many
hours; say so when you ask Jon to start one. Optimization advice lives in
`references/optimization.md`; quote thresholds from there.

## Pitfalls

- A pool can be `ONLINE` with a failing disk. Check SMART, not only status.
- `disk.temperatures` caches for 5 minutes; one reading is not a trend.
- bignas is on 25.04, fastnas on 25.10: method names and results differ
  (SMART is bignas only). When a method is missing, use `--methods <word>`.
- A new NAS user without access returns an auth failure, not an empty list.

## Sensitive data

The repo and chat history are public or permanent. Never print an API key.
Report disk serials, share names and dataset names only when the question
is about that object; otherwise give counts.
