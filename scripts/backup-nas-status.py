#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["websockets>=12"]
# ///
"""Read-only status of the orion backup landing zone on both NASes (GH #322).

  python3 scripts/backup-nas-status.py

Per box (bignas, fastnas) it reports pool health, the backups/orion datasets,
their NFS exports (restricted vs open), the snapshot task covering the tree,
and active alerts. Exit 0 when everything is in place on every reachable box,
1 when something is missing or wrong, 2 when no box was reachable.

Credentials come from the environment, matching Secret/hermes-secrets:
TRUENAS_<NAS>_URL / TRUENAS_<NAS>_API_KEY, falling back to <NAS>_URL /
<NAS>_API_KEY. Keys are never printed and every request is https-only.

The agent-maint NAS user is read-only on purpose (see the hermes-hearth
truenas skill), so this script only ever reads.
"""

import asyncio
import json
import os
import sys

import websockets

TREE = "backups/orion"
LEAF_DATASETS = (f"{TREE}/tier1-critical", f"{TREE}/tier2-bulk")
KEEP_VALUE, KEEP_UNIT = 14, "DAYS"
# bignas (25.04) and fastnas (25.10) name the snapshot query differently.
SNAPSHOT_METHOD = {"bignas": "zfs.snapshot.query", "fastnas": "pool.snapshot.query"}

PHASE1 = (
    ("system.info", []),
    ("pool.query", []),
    ("pool.dataset.query", []),
    ("sharing.nfs.query", []),
    ("pool.snapshottask.query", []),
    ("alert.list", []),
    ("service.query", []),
    ("smart.test.results", []),  # bignas only; errors elsewhere are ignored
)


def creds(nas: str) -> tuple[str, str]:
    env = nas.upper()
    url = os.environ.get(f"TRUENAS_{env}_URL") or os.environ.get(f"{env}_URL") or ""
    key = os.environ.get(f"TRUENAS_{env}_API_KEY") or os.environ.get(f"{env}_API_KEY") or ""
    return url, key


async def session(url: str, key: str, calls: list[tuple[str, list]]) -> list[dict]:
    if not url.startswith("https://"):
        sys.exit("refused: URL must be https:// (an API key sent over http is revoked)")
    ws_url = "wss://" + url[len("https://"):].rstrip("/") + "/api/current"
    async with websockets.connect(ws_url, max_size=None, open_timeout=15) as ws:
        async def send(i, m, p):
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": i, "method": m, "params": p}))

        async def collect(ids):
            got = {}
            while ids - got.keys():
                msg = json.loads(await asyncio.wait_for(ws.recv(), 90))
                if msg.get("id") in ids:
                    got[msg["id"]] = msg
            return got

        await send(1, "auth.login_with_api_key", [key])
        if (await collect({1}))[1].get("result") is not True:
            raise RuntimeError("auth failed (missing/revoked key, or user lacks access)")
        for i, (m, p) in enumerate(calls, start=2):
            await send(i, m, p)
        got = await collect(set(range(2, len(calls) + 2)))
        return [got[i] for i in range(2, len(calls) + 2)]


def rows(x):
    return [r for r in x if isinstance(r, dict)] if isinstance(x, list) else []


def pool_line(pool: dict) -> str:
    scan = pool.get("scan") or {}
    fn, state = scan.get("function", ""), scan.get("state", "")
    errs = scan.get("errors", "?")
    size, alloc = pool.get("size") or 0, pool.get("allocated") or 0
    pct = f"{100 * alloc / size:.1f}%" if size else "?"
    parts = [f"{pool.get('name', '?')}: {pool.get('status', '?')}"
             f"{' healthy' if pool.get('healthy') else ' NOT HEALTHY'}"]
    if fn:
        parts.append(f"{fn.lower()} {state.lower()} (errors: {errs})")
    parts.append(f"{pct} used")
    return ", ".join(parts)


def daily(schedule: dict) -> bool:
    s = schedule or {}
    return s.get("dom") == "*" and s.get("month") == "*" and s.get("dow") == "*"


def task_shape(t: dict) -> str:
    bits = ["daily" if daily(t.get("schedule")) else "not daily",
            f"keep {t.get('lifetime_value', '?')} {t.get('lifetime_unit', '?')}",
            f"{'recursive' if t.get('recursive') else 'non-recursive'}",
            "enabled" if t.get("enabled") else "DISABLED"]
    if t.get("state"):
        bits.append(f"last run {t['state'].lower()}")
    return ", ".join(bits)


def analyze(nas: str, replies: list[dict]) -> tuple:
    ok, err = {}, {}
    for (method, _), r in zip(PHASE1, replies):
        (ok if "result" in r and "error" not in r else err)[method] = r.get("result", r.get("error"))

    out = {"nas": nas, "problems": []}

    info = ok.get("system.info") if isinstance(ok.get("system.info"), dict) else {}
    out["version"] = info.get("version") or "unknown version"

    pools = rows(ok.get("pool.query"))
    out["pools"] = [pool_line(p) for p in pools]
    for p in pools:
        if p.get("status") != "ONLINE" or not p.get("healthy"):
            out["problems"].append(f"pool {p.get('name', '?')} is not ONLINE/healthy")

    # Derive the pool prefix from any dataset that ends with a leaf name.
    datasets = rows(ok.get("pool.dataset.query"))
    prefix = ""
    for d in datasets:
        for leaf in LEAF_DATASETS:
            if d.get("name", "").endswith("/" + leaf):
                prefix = d["name"][: -(len(leaf) + 1)]
                break
    out["datasets"] = {}
    for leaf in LEAF_DATASETS:
        full = f"{prefix}/{leaf}" if prefix else leaf
        if any(d.get("name") == full for d in datasets):
            out["datasets"][leaf] = "present"
        else:
            out["datasets"][leaf] = "MISSING"
            out["problems"].append(f"dataset {leaf} missing")

    exports = rows(ok.get("sharing.nfs.query"))
    out["exports"] = {}
    for leaf in LEAF_DATASETS:
        full = f"{prefix}/{leaf}" if prefix else leaf
        path = f"/mnt/{full}"
        match = [e for e in exports if e.get("path") == path]
        if not match:
            out["exports"][leaf] = "MISSING"
            out["problems"].append(f"nfs export for {leaf} missing")
            continue
        nets, hosts = match[0].get("networks") or [], match[0].get("hosts") or []
        if nets or hosts:
            out["exports"][leaf] = f"restricted ({', '.join(nets + hosts)})"
        else:
            out["exports"][leaf] = "OPEN to any host"
            out["problems"].append(f"nfs export for {leaf} is not restricted to node IPs")

    # A task may sit on the tree (recursive) or on each leaf dataset.
    def covers(name: str) -> bool:
        return name.endswith("/" + TREE) and (name[: -(len(TREE) + 1)] == prefix) or name in (
            f"{prefix}/{LEAF_DATASETS[0]}", f"{prefix}/{LEAF_DATASETS[1]}")

    tasks = [t for t in rows(ok.get("pool.snapshottask.query")) if covers(t.get("dataset", ""))]
    out["snapshot_tasks"] = [(t.get("dataset", "?"), task_shape(t)) for t in tasks]
    good_tasks = [t for t in tasks if t.get("enabled") and daily(t.get("schedule"))
                  and t.get("lifetime_value") == KEEP_VALUE and t.get("lifetime_unit") == KEEP_UNIT
                  and (t.get("dataset", "").endswith("/" + TREE) and t.get("recursive")
                       or t.get("dataset") in (f"{prefix}/{LEAF_DATASETS[0]}", f"{prefix}/{LEAF_DATASETS[1]}"))]
    if not good_tasks:
        want = f"daily, keep {KEEP_VALUE} {KEEP_UNIT}, recursive on {TREE} (or on both leaves)"
        out["problems"].append(f"no matching snapshot task ({want})")

    services = rows(ok.get("service.query"))
    out["nfs_service"] = next((s.get("state") for s in services if s.get("service") == "nfs"), "unknown")
    if out["nfs_service"] != "RUNNING":
        out["problems"].append(f"nfs service is {out['nfs_service']}, not RUNNING")

    alerts = [a for a in rows(ok.get("alert.list")) if not a.get("dismissed")]
    out["alerts"] = len(alerts)

    if "smart.test.results" in ok:
        tests = rows(ok["smart.test.results"])
        latest = []
        for t in tests:
            last = next(iter(rows(t.get("tests"))), {})
            latest.append(f"{t.get('disk', '?')}: {last.get('status', 'no results')}")
        out["smart"] = "; ".join(latest) if latest else "no results recorded"
    elif "smart.test.results" in err:
        out["smart"] = "unavailable (API error on this build; check alerts instead)"

    return out, ok, err, prefix


async def snapshots_probe(nas: str, url: str, key: str, prefix: str, method: str) -> str:
    """Best-effort newest-snapshot timestamp for the tree (one extra login)."""
    if not prefix:
        return "no datasets yet"
    flt = [["name", "^=", f"{prefix}/{TREE}"]]
    try:
        replies = await session(url, key, [(method, [flt])])
        if "error" in replies[0]:
            return "unavailable"
        snaps = rows(replies[0].get("result"))
        if not snaps:
            return "none yet"
        newest = max(snaps, key=lambda s: (s.get("properties") or {}).get("creation", {}).get("rawvalue", ""))
        return f"newest {newest.get('name', '?')}"
    except Exception:
        return "unavailable"


def verdict_line(out: dict) -> str:
    return f"  verdict: {'READY' if not out['problems'] else 'NOT READY — ' + '; '.join(out['problems'])}"


def report(nas: str, out: dict, snapshots: str) -> str:
    lines = [f"== {nas} ({out['version']}) =="]
    lines += [f"  pool {p}" for p in out["pools"]]
    lines.append(f"  nfs service: {out['nfs_service']}")
    for leaf, state in out["datasets"].items():
        lines.append(f"  dataset {leaf:<28} {state}")
    for leaf, state in out["exports"].items():
        lines.append(f"  export  {leaf:<28} {state}")
    if out["snapshot_tasks"]:
        for ds, shape in out["snapshot_tasks"]:
            lines.append(f"  snapshot task {ds}: {shape}")
    else:
        lines.append(f"  snapshot task: MISSING (want daily, keep {KEEP_VALUE} {KEEP_UNIT} on {TREE})")
    lines.append(f"  snapshots on tree: {snapshots}")
    if "smart" in out:
        lines.append(f"  smart test results: {out['smart']}")
    lines.append(f"  active alerts: {out['alerts']}")
    lines.append(verdict_line(out))
    return "\n".join(lines)


async def box(nas: str) -> tuple[str, bool, bool]:
    """Returns (report_text, ready, reachable)."""
    url, key = creds(nas)
    if not url or not key:
        return (f"== {nas} ==\n  skipped — set TRUENAS_{nas.upper()}_URL and "
                f"TRUENAS_{nas.upper()}_API_KEY (or {nas.upper()}_URL/{nas.upper()}_API_KEY)", False, False)
    replies = await session(url, key, list(PHASE1))
    out, ok, err, prefix = analyze(nas, replies)
    snap_method = SNAPSHOT_METHOD.get(nas, "zfs.snapshot.query")
    snaps = await snapshots_probe(nas, url, key, prefix, snap_method)
    return report(nas, out, snaps), not out["problems"], True


async def main() -> int:
    reports, readies, reachable = [], [], 0
    for nas in ("bignas", "fastnas"):
        try:
            text, ready, ok = await box(nas)
            reports.append(text)
            readies.append(ready)
            reachable += ok
        except Exception as e:  # noqa: BLE001 — status tool must never trace back a key
            reports.append(f"== {nas} ==\n  unreachable: {e}")
    print("\n\n".join(reports))
    if not reachable:
        print("\nno NAS reachable — check credentials and https URLs")
        return 2
    return 0 if all(readies) else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
