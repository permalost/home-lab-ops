---
name: truenas
description: "Check, troubleshoot and tune the two TrueNAS boxes: fastnas (SSD) and bignas (HDD). Pool health, capacity, scrubs, SMART, disk temps, alerts, snapshots, replication, ARC, updates. Can start a scrub, a SHORT/LONG SMART test, or an agent- snapshot; nothing else changes."
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

Exactly three actions. For everything else, recommend it and say what it
risks; do not do it.

1. Start a pool scrub (`pool.scrub.scrub` with `START`).
2. Start a `SHORT` or `LONG` SMART test (`smart.test.manual_test`).
3. Create a snapshot named `agent-<YYYYMMDD-HHMM>` (`pool.snapshot.create`
   on fastnas, `zfs.snapshot.create` on bignas).

Before any of them: no scrub while a scrub or resilver runs
(`pool.query` -> `scan`); no LONG test on a disk that is already testing.
One action per request. Report the job id and how to watch it
(`core.get_jobs`). Never delete, rollback, edit pool/dataset/share/network
settings, apply updates, reboot, or offline a disk.

`scripts/tn.py` refuses anything outside this list, and the NAS user
`agent-maint` has no wider role. If either fence blocks you, stop and say so.

## Use the helper

All calls go through `scripts/tn.py` (JSON-RPC over WebSocket, same on both
versions). Run `python3 scripts/tn.py ...` from this skill's directory; if
`websockets` is missing, `pip install --user websockets` first (`uv run` also works).

```bash
python3 scripts/tn.py bignas pool.query
python3 scripts/tn.py bignas smart.test.results
python3 scripts/tn.py bignas pool.scrub.scrub '["tank", "START"]'
python3 scripts/tn.py fastnas --methods smart      # find a renamed method
```

Why not curl: fastnas (25.10) dropped REST for SMART, update checks and
`zfs.snapshot`. See `references/api.md`. Keys must travel over HTTPS only;
TrueNAS revokes a key used over plain HTTP, and the helper refuses `http://`.

## Procedure: health check

Do this per NAS, cheapest first. Stop and report as soon as something
explains the complaint.

1. `alert.list` — anything not dismissed? These are the NAS's own findings.
2. `pool.query` — `status` is `ONLINE`, `healthy` true, no errors in
   `topology`, `scan` shows last scrub and its errors.
3. Capacity: `size`/`allocated` -> warn at 80% used, act at 90%.
4. `disk.query` + `disk.temperatures` — temps (limits in `references/optimization.md`).
5. SMART: `smart.test.results` — any FAILED, or none in 35 days (HDD) / 90 days (SSD).
   Also `disk.smart_attributes` on HDDs: reallocated, pending, offline-uncorrectable > 0.
6. `pool.snapshottask.query` + `pool.snapshot.query` (fastnas) /
   `zfs.snapshot.query` (bignas) — newest snapshot older than its task
   interval means the task is failing.
7. `replication.query`, `cloudsync.query` — `job.state` FAILED?
8. Updates: `update.status` (fastnas) / `update.check_available` (bignas).
9. `boot.get_state` — boot pool healthy.

If all clean, say so in two lines. Do not keep digging.

## Procedure: one symptom

| Symptom | Look at |
|---|---|
| Slow reads/writes | `pool.query` scan (scrub/resilver running?), `reporting.get_data` ARC and disk busy, temps (HDD thermal throttle), pool > 80% full |
| Alert emailed | `alert.list`, then the object it names |
| Disk "degraded" | `pool.query` topology, `smart.test.results`, `smart_attributes` for that disk |
| Pool filling | `pool.dataset.query` sorted by `used`, `snapshot_count`; snapshots are the usual cause |
| Share unreachable | `service.query` (smb/nfs running?), `alert.list`; if the NAS answers here, the problem is network or share config, not the pool |

## Report

Write it for the person who owns the NAS. Per issue: what is wrong in plain
words (not the raw field), the specific action, and its side effects. A
scrub slows the pool for hours; a LONG test on an HDD adds load for
many hours; say so before running either. Optimization advice lives in
`references/optimization.md`; quote thresholds from there.

## Pitfalls

- A pool can be `ONLINE` with a failing disk. Check SMART, not only status.
- `disk.temperatures` caches for 5 minutes; one reading is not a trend.
- bignas is on 25.04, fastnas on 25.10: method paths and results differ.
  When a method is missing, use `--methods <word>`.
- A new NAS user without access returns an auth failure, not an empty list.

## Sensitive data

The repo and chat history are public or permanent. Never print an API key.
Report disk serials, share names and dataset names only when the question
is about that object; otherwise give counts.
