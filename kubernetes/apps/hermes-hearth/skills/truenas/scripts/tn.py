#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["websockets>=12"]
# ///
"""Call a TrueNAS middleware method over JSON-RPC 2.0 / WebSocket.

  tn.py <nas> <method> [params-json]     e.g. tn.py bignas pool.query
  tn.py <nas> --methods [substring]      list method names (find renamed ones)

<nas> is "fastnas" or "bignas". Reads <NAS>_URL and <NAS>_API_KEY from the
environment (https://host, API key). The key is never printed.

Client-side guard: read-only methods and a short write allow-list only. This
is a second fence; the real limit is the NAS user's role (see SKILL.md).
"""
import asyncio
import json
import os
import re
import sys

import websockets

READ = re.compile(
    r"\.(query|get_instance|config|status|results|temperatures?|temperature_agg"
    r"|smart_attributes|get_state|get_methods|list|info|version|get_jobs"
    r"|check_available|get_pending|available_versions)$"
)
WRITE = {"pool.scrub.run", "pool.scrub.scrub", "smart.test.manual_test",
         "pool.snapshot.create", "zfs.snapshot.create"}


def check(method: str, params: list) -> None:
    if READ.search(method):
        return
    if method not in WRITE:
        sys.exit(f"refused: {method} is not read-only or on the write allow-list")
    first = params[0] if params else None
    if method == "pool.scrub.scrub" and not (len(params) == 2 and params[1] == "START"):
        sys.exit("refused: pool.scrub.scrub only allows action START")
    if method == "smart.test.manual_test":
        tests = first if isinstance(first, list) else []
        if not tests or any(t.get("type") not in ("SHORT", "LONG") for t in tests):
            sys.exit("refused: only SHORT or LONG SMART tests")
    if method.endswith("snapshot.create"):
        name = (first or {}).get("name", "") if isinstance(first, dict) else ""
        if not name.startswith("agent-"):
            sys.exit("refused: snapshot name must start with agent-")


async def call(nas: str, method: str, params: list):
    env = nas.upper()
    url, key = os.environ.get(f"{env}_URL"), os.environ.get(f"{env}_API_KEY")
    if not url or not key:
        sys.exit(f"set {env}_URL and {env}_API_KEY")
    if not url.startswith("https://"):
        sys.exit("refused: URL must be https:// (an API key sent over http is revoked)")
    ws_url = "wss://" + url[len("https://"):].rstrip("/") + "/api/current"

    async with websockets.connect(ws_url, max_size=None, open_timeout=15) as ws:
        async def rpc(i: int, m: str, p: list):
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": i, "method": m, "params": p}))
            while True:
                msg = json.loads(await asyncio.wait_for(ws.recv(), 60))
                if msg.get("id") == i:
                    return msg

        auth = await rpc(1, "auth.login_with_api_key", [key])
        if auth.get("result") is not True:
            sys.exit("auth failed (key revoked, wrong NAS, or user lacks access)")
        return await rpc(2, method, params)


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    nas, method = sys.argv[1], sys.argv[2]
    if nas not in ("fastnas", "bignas"):
        sys.exit("nas must be fastnas or bignas")
    if method == "--methods":
        needle = sys.argv[3] if len(sys.argv) > 3 else ""
        res = asyncio.run(call(nas, "core.get_methods", []))
        names = sorted(k for k in res.get("result", {}) if needle in k)
        print("\n".join(names))
        return
    params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else []
    check(method, params)
    print(json.dumps(asyncio.run(call(nas, method, params)), indent=2))


if __name__ == "__main__":
    main()
