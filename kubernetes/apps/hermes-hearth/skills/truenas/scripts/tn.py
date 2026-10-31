#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["websockets>=12"]
# ///
"""Call a TrueNAS middleware method over JSON-RPC 2.0 / WebSocket.

  tn.py <nas> --health                   one-shot health summary (JSON)
  tn.py <nas> <method> [params-json]     e.g. tn.py bignas pool.query
  tn.py <nas> --methods [substring]      list method names (find renamed ones)

<nas> is "fastnas" or "bignas". Reads <NAS>_URL and <NAS>_API_KEY from the
environment (https://host, API key). The key is never printed.

Client-side guard: read-only methods plus agent- snapshot creation only. This
is a second fence; the real limit is the NAS user's role (see SKILL.md).
"""
import asyncio
import json
import os
import re
import sys
from datetime import datetime, timezone

import websockets

READ = re.compile(
    r"\.(query|get_instance|config|status|results|temperatures?|temperature_agg"
    r"|get_state|get_methods|list|info|version|get_jobs"
    r"|check_available|get_pending|available_versions)$"
)
WRITE = {"pool.snapshot.create", "zfs.snapshot.create"}

# Calls for --health, sent together over one login. Each may fail on one
# version (method missing, no role); a failure is reported under
# "unavailable", not fatal.
HEALTH_CALLS = [
    ("system.info", []),
    ("alert.list", []),
    ("pool.query", []),
    ("disk.query", []),
    ("disk.temperatures", [[]]),           # empty list = all disks
    ("smart.test.results", []),            # bignas (25.04) only
    ("pool.snapshottask.query", []),
    ("replication.query", []),
    ("cloudsync.query", []),
    ("service.query", []),
    ("boot.get_state", []),
    ("update.status", []),                 # fastnas (25.10)
    ("update.check_available", []),        # bignas (25.04)
]


def check(method: str, params: list) -> None:
    if READ.search(method):
        return
    if method not in WRITE:
        sys.exit(f"refused: {method} is not read-only or on the write allow-list")
    first = params[0] if params else None
    name = (first or {}).get("name", "") if isinstance(first, dict) else ""
    if not name.startswith("agent-"):
        sys.exit("refused: snapshot name must start with agent-")


async def session(nas: str, calls: list[tuple[str, list]]) -> list[dict]:
    """Log in once, send every call together, return responses in order."""
    env = nas.upper()
    url, key = os.environ.get(f"{env}_URL"), os.environ.get(f"{env}_API_KEY")
    if not url or not key:
        sys.exit(f"set {env}_URL and {env}_API_KEY")
    if not url.startswith("https://"):
        sys.exit("refused: URL must be https:// (an API key sent over http is revoked)")
    ws_url = "wss://" + url[len("https://"):].rstrip("/") + "/api/current"

    async with websockets.connect(ws_url, max_size=None, open_timeout=15) as ws:
        async def send(i: int, m: str, p: list) -> None:
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": i, "method": m, "params": p}))

        async def collect(ids: set) -> dict:
            got = {}
            while ids - got.keys():
                msg = json.loads(await asyncio.wait_for(ws.recv(), 90))
                if msg.get("id") in ids:
                    got[msg["id"]] = msg
            return got

        await send(1, "auth.login_with_api_key", [key])
        if (await collect({1}))[1].get("result") is not True:
            sys.exit("auth failed (key revoked, wrong NAS, or user lacks access)")
        for i, (m, p) in enumerate(calls, start=2):
            await send(i, m, p)
        got = await collect(set(range(2, len(calls) + 2)))
        return [got[i] for i in range(2, len(calls) + 2)]


# ---- health summary -------------------------------------------------------

def fix(v):
    """Make middleware values readable: {"$date": ms} -> ISO string."""
    if isinstance(v, dict):
        if set(v) == {"$date"}:
            return datetime.fromtimestamp(v["$date"] / 1000, timezone.utc).isoformat()
        return {k: fix(x) for k, x in v.items()}
    if isinstance(v, list):
        return [fix(x) for x in v]
    return v


def rows(x) -> list:
    """Only the dict rows of a list reply; anything else (a reshaped reply) is empty."""
    return [r for r in x if isinstance(r, dict)] if isinstance(x, list) else []


def pick(d: dict, keys: tuple) -> dict:
    return {k: d[k] for k in keys if k in d}


def bad_vdevs(node, out: list) -> None:
    """Collect any vdev/disk that is not ONLINE or has errors."""
    if isinstance(node, list):
        for n in node:
            bad_vdevs(n, out)
    elif isinstance(node, dict):
        stats = node.get("stats") or {}
        errs = sum(stats.get(k) or 0 for k in ("read_errors", "write_errors", "checksum_errors"))
        if node.get("status") not in (None, "ONLINE") or errs:
            out.append({"name": node.get("name") or node.get("path"),
                        "status": node.get("status"), "errors": errs})
        for k in ("children", "data", "cache", "log", "spare", "special", "dedup"):
            bad_vdevs(node.get(k), out)


def pool_row(p: dict) -> dict:
    size, used = p.get("size") or 0, p.get("allocated") or 0
    scan = fix(p.get("scan") or {})
    bad: list = []
    bad_vdevs(p.get("topology"), bad)
    row = pick(p, ("name", "status", "healthy"))
    row.update(percent_used=round(100 * used / size, 1) if size else None,
               scan=pick(scan, ("function", "state", "end_time", "percentage", "errors")),
               bad_vdevs=bad)
    return row


def summarize(nas: str, calls, replies) -> dict:
    ok, unavailable = {}, {}
    for (method, _), r in zip(calls, replies):
        if "error" in r:
            unavailable[method] = str(r["error"].get("message", r["error"]))[:160]
        else:
            ok[method] = fix(r.get("result"))

    out: dict = {"nas": nas}
    info = ok.get("system.info") if isinstance(ok.get("system.info"), dict) else {}
    out["system"] = pick(info, ("version", "uptime_seconds", "loadavg"))
    out["alerts"] = [pick(a, ("level", "klass", "formatted"))
                     for a in rows(ok.get("alert.list")) if not a.get("dismissed")]
    out["pools"] = [pool_row(p) for p in rows(ok.get("pool.query"))]

    disks = rows(ok.get("disk.query"))
    temps = ok.get("disk.temperatures")
    temps = temps if isinstance(temps, dict) else {}
    out["disks"] = [{**pick(d, ("name", "model", "type", "rotationrate", "pool", "size")),
                     "temp_c": temps.get(d.get("name"))} for d in disks]

    tests = ok.get("smart.test.results")
    if tests is not None:
        out["smart_latest"] = [
            {"disk": t.get("disk"), **pick(next(iter(rows(t.get("tests"))), {}),
             ("description", "status", "lifetime"))} for t in rows(tests)]

    out["snapshot_tasks"] = [pick(t, ("dataset", "enabled", "lifetime_value", "lifetime_unit",
                                      "state")) for t in rows(ok.get("pool.snapshottask.query"))]
    out["replication"] = [pick(t, ("name", "enabled", "state")) for t in rows(ok.get("replication.query"))]
    out["cloudsync"] = [pick(t, ("description", "enabled", "job")) for t in rows(ok.get("cloudsync.query"))]
    out["services"] = {s["service"]: s.get("state") for s in rows(ok.get("service.query"))
                       if s.get("service") in ("cifs", "smb", "nfs", "ssh")}
    out["boot"] = pick(ok.get("boot.get_state") if isinstance(ok.get("boot.get_state"), dict) else {}, ("status", "healthy"))
    out["update"] = ok.get("update.status") or ok.get("update.check_available")
    out["unavailable"] = unavailable
    return out


async def health(nas: str) -> dict:
    for m, p in HEALTH_CALLS:
        check(m, p)
    return summarize(nas, HEALTH_CALLS, await session(nas, HEALTH_CALLS))


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    nas, method = sys.argv[1], sys.argv[2]
    if nas not in ("fastnas", "bignas"):
        sys.exit("nas must be fastnas or bignas")
    if method == "--health":
        print(json.dumps(asyncio.run(health(nas)), indent=2))
        return
    if method == "--methods":
        needle = sys.argv[3] if len(sys.argv) > 3 else ""
        res = asyncio.run(session(nas, [("core.get_methods", [])]))[0]
        names = sorted(k for k in res.get("result", {}) if needle in k)
        print("\n".join(names))
        return
    params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else []
    check(method, params)
    print(json.dumps(asyncio.run(session(nas, [(method, params)]))[0], indent=2))


if __name__ == "__main__":
    main()
