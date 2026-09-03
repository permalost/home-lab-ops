---
name: unifi
description: "UniFi network controller API via curl. Health, devices, WiFi/RF, clients, DHCP, VLANs, firewall, events, alarms — network troubleshooting and status checks."
version: 0.1.0
author: community
license: MIT
platforms: [linux, macos, windows]
prerequisites:
  env_vars: [UNIFI_URL, UNIFI_USER, UNIFI_PASSWORD]
  commands: [curl]
metadata:
  hermes:
    tags: [UniFi, Network, WiFi, Ubiquiti, Troubleshooting]
    homepage: https://ui.com
    related_skills: []
---

# UniFi Network

UniFi Dream Machine / Cloud Gateway controller API via curl, session cookie
+ CSRF token. Read-only — this skill queries status and diagnoses problems,
it doesn't push config changes, restart devices, or otherwise write to the
controller. If a task needs a config change, say so rather than attempting
it.

## When to Use

- "Is the network OK?" / "Check the WiFi" / periodic health check
- "Is `<device>` connected?" / "Why can't `<device>` get online?"
- "Is the WiFi congested?" / "How many clients are on `<AP/SSID>`?"
- "Any recent network alarms/errors?"
- "Is `<port>` forwarded?" / "What VLANs exist?"

## Prerequisites

- `UNIFI_URL` — `https://unifi.orion.norseamerican.com` (already set in this
  deployment's env). Goes through the cluster Gateway to the physical
  controller — this is a real device on the home LAN, not an in-cluster
  service.
- `UNIFI_USER` / `UNIFI_PASSWORD` — controller login (already set).

## Auth

Every call needs a session cookie *and* a CSRF token from login. `curl`'s
cookie jar handles the cookie; the CSRF token has to be pulled out of the
response headers by hand and re-sent on every request after.

```bash
curl -s -c /tmp/unifi-cookies.txt -D /tmp/unifi-headers.txt -o /dev/null \
  -X POST "$UNIFI_URL/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$UNIFI_USER\",\"password\":\"$UNIFI_PASSWORD\"}"

CSRF=$(grep -i '^x-csrf-token:' /tmp/unifi-headers.txt | tail -1 | tr -d '\r' | awk '{print $2}')
```

Then on every subsequent request, send `-b /tmp/unifi-cookies.txt -H "X-CSRF-Token: $CSRF"`.
If a response includes an `x-updated-csrf-token` header, that's a refreshed
token — use it for the next call instead of the one from login (long chains
of calls can otherwise start failing partway through with a stale token).

Requests don't need `-k`/insecure mode here — `UNIFI_URL` goes through the
cluster Gateway, which already validates the hop to the controller's
self-signed cert. If TLS verification ever fails, that's worth actually
looking into (e.g. the Gateway's own cert or the cluster CA bundle) rather
than reflexively adding `-k`.

## Quick Reference

All paths below are relative to `$UNIFI_URL/proxy/network/api/s/default/`,
except System (root-level). Data comes back as `{"data": [...]}` — pull the
`data` field.

| What | Path | Notes |
|---|---|---|
| System info | `$UNIFI_URL/api/system` | root, not under `/proxy/network/` — hardware, firmware, uptime |
| Health | `stat/health` | per-subsystem status; anything not `"ok"` is worth surfacing |
| Devices | `stat/device` | APs/switches/gateway; `type`: `uap`/`usw`/`ugw`; `state` 0=down 1=up 4=upgrading |
| Active clients | `stat/sta` | connected now; `signal`/`rssi`, `essid`, `hostname`/`mac` |
| One client (incl. offline) | `stat/user/{mac}` | last-seen info even if not currently connected |
| Networks/VLANs | `rest/networkconf` | `purpose`, `ip_subnet`, `vlan`, `dhcpd_*` |
| DHCP leases | `stat/dhcp/lease` | join to networks via `network_id` |
| WLANs | `rest/wlanconf` | security, WPA3/PMF, `fast_roaming_enabled`, `bss_transition` |
| Firewall rules | `rest/firewallrule` | `ruleset` (`WAN_IN`/`LAN_IN`/`LAN_LOCAL`), `action`, `src`/`dst` |
| Port forwards | `rest/portforward` | |
| Event log | `stat/event?within=<hours>` | `key` categorizes (`EVT_AP_Lost_Contact` etc), `client`/`user` is the MAC |
| Alarms | `list/alarm` | `archived` flag, `key`, `msg` |

Example — active clients:

```bash
curl -s -b /tmp/unifi-cookies.txt -H "X-CSRF-Token: $CSRF" \
  "$UNIFI_URL/proxy/network/api/s/default/stat/sta" | python3 -m json.tool
```

## Procedure: quick health triage

No specific symptom given — check these in order, cheapest/most-likely
first, and stop as soon as something explains it:

1. `stat/health` — any subsystem not `"ok"`?
2. `stat/device` — any device with `state` not `1` (excluding `4`,
   mid-upgrade)?
3. `stat/event?within=24` — any `EVT_AP_Lost_Contact` / `EVT_SW_Lost_Contact`
   / `EVT_GW_Lost_Contact` in the last day?
4. `list/alarm` — any entry with `"archived": false`?

If all four are clean, the network is fine — don't keep digging
speculatively; ask for a more specific symptom instead.

## Procedure: device/client connectivity

1. `stat/sta` — is it in the currently-connected list? If yes, it's
   connected at the network layer — an app-level problem (DNS, firewall)
   is more likely than a connectivity one.
2. Not there? `stat/user/{mac}` for last-seen info.
3. Check its network's DHCP pool isn't full: `rest/networkconf` for the
   `dhcpd_start`/`dhcpd_stop` range, `stat/dhcp/lease` for how many are
   taken. A full pool is a common "new device can't get an IP, others are
   fine" cause.
4. `stat/event?within=168` filtered to that MAC for repeated
   disconnect/auth-failure events — usually points to a wrong
   password/PSK rather than DHCP.

## Procedure: WiFi congestion / slowness

`stat/device`, filter `type == "uap"`, read `radio_table_stats` per band
(`ng`=2.4GHz, `na`=5GHz, `6e`=6GHz):

- `cu_total` (channel utilization) above ~70% → the radio is airtime-limited,
  not signal-limited; that's why it's slow even if bars look full.
- `num_sta` above ~30 on one radio → crowded; needs another AP to split
  load, not a config tweak.
- `satisfaction` below 50% → UniFi's own composite score for a bad
  experience on that radio, even if individual numbers look borderline OK.

For one client specifically, `stat/sta`: `signal`/`rssi` below −75 dBm is
poor (coverage issue, not congestion); `tx_retries/tx_packets` above ~15%
(with `tx_packets > 100` to filter noise) means the air itself is unreliable
for that client.

## Pitfalls

- **UniFi allows inter-VLAN routing by default.** No `LAN_IN`/`LAN_LOCAL`
  firewall rules doesn't mean nothing's wrong — if a VLAN's name implies
  isolation (iot/cam/guest), the absence of rules means it has *no*
  isolation, not that isolation is working.
- **CSRF token goes stale.** If a call starts failing partway through a
  long sequence with an auth-shaped error, re-check for an
  `x-updated-csrf-token` in the last successful response before assuming
  the whole session died.
- **`state: 4` is not down** — it's mid-firmware-upgrade. Don't report a
  device as offline without checking this first.
- A single weak-signal or high-retry reading is noisy/momentary on its own;
  a pattern across multiple checks or repeated events is much stronger
  signal than one snapshot.

## Verification

```bash
curl -s -b /tmp/unifi-cookies.txt -H "X-CSRF-Token: $CSRF" \
  "$UNIFI_URL/proxy/network/api/s/default/stat/health" | python3 -m json.tool
```

Expect a list of subsystems, most/all `"status": "ok"`.
