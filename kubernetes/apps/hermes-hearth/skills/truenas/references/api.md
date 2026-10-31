# TrueNAS API notes

Checked against the live OpenAPI specs of fastnas (25.10) and bignas (25.04)
on 2026-10-31. Re-check after a major upgrade:
`curl -sk https://<nas>/api/v2.0/openapi.json` needs no login.

## Transport

JSON-RPC 2.0 over `wss://<host>/api/current`, via `scripts/tn.py`. Log in
first with `auth.login_with_api_key [key]`; the helper does this. Methods
use middleware names (`pool.query`), not URLs. Job methods return a job id.

REST (`/api/v2.0/...`) works for most reads but is deprecated and already
incomplete on 25.10. Use it only to read the spec.

## Where 25.10 differs from 25.04

| Need | bignas (25.04) | fastnas (25.10) |
|---|---|---|
| SMART results / tests / attributes | `smart.test.results`, `smart.test.manual_test`, `disk.smart_attributes` | not in REST; try `tn.py fastnas --methods smart` |
| Snapshots | `zfs.snapshot.query` / `.create` | `pool.snapshot.query` / `.create` |
| Update check | `update.check_available`, `update.get_pending` | `update.status` |
| Disk temperature | `disk.temperature`, `disk.temperatures` | `disk.temperatures`, `disk.temperature_agg` |
| Scrub | `pool.scrub.scrub [pool, "START"]` | same |

If a method is not found, run `--methods <word>`; do not guess names.

## Calls used by the health check

| Method | Gives |
|---|---|
| `alert.list` | active alerts (`dismissed`, `level`, `formatted`) |
| `pool.query` | `status`, `healthy`, `scan` (scrub/resilver), `topology`, `size`, `allocated` |
| `pool.dataset.query` | `used`, `available`, per-dataset properties |
| `disk.query` | model, serial, `rotationrate` (null = SSD), `pool` |
| `disk.temperatures` | degrees C; cached 5 min (body key is `name` on fastnas, `names` on bignas) |
| `pool.snapshottask.query` | schedule and retention |
| `replication.query`, `cloudsync.query` | `job.state`, last run |
| `service.query` | smb/nfs/ssh `state` |
| `boot.get_state` | boot pool health |
| `reporting.get_data` | ARC hit ratio, disk busy, load |
| `core.get_jobs` | progress of a started scrub/test |

## Writes (the only three)

```bash
python3 scripts/tn.py bignas pool.scrub.scrub '["tank", "START"]'
python3 scripts/tn.py bignas smart.test.manual_test '[[{"identifier": "sda", "type": "SHORT"}]]'
python3 scripts/tn.py fastnas pool.snapshot.create '[{"dataset": "tank/data", "name": "agent-20261031-1200"}]'
```

On bignas use `zfs.snapshot.create` with the same body.

## Access

User `agent-maint` on each NAS, in a group whose privilege is Read-only
Admin plus the write roles for scrubs, SMART tests and snapshots. No shell,
no SMB. One API key per NAS. TrueNAS revokes a key used over plain HTTP:
keep every URL `https://`.
