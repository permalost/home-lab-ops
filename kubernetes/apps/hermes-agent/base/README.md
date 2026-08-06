# hermes-agent/base — shared Hermes Agent tier

Not a standalone overlay — like `webapp/base`, it contains the unresolved
`${appName}` substitution token and is excluded from direct build/lint
validation in `scripts/validate.sh`. Consumed by
`kubernetes/apps/hermes-agent/overlays/<profile>/`, one per Hermes profile
(persona), the same relationship `pihole2/base` has to
`pihole2/overlays/orion`.

Fixes everything common to every profile: the `nousresearch/hermes-agent`
image, gateway (8642) + dashboard (9119) ports, the dashboard exposed via
`httproute` on port 80 (matching the component's hardcoded backend port,
same workaround `pihole2` uses), health probes, default resource sizing,
and the volume layout below.

## Volume contract

| Path | Source | Writable | Notes |
|---|---|---|---|
| `/opt/data` | PVC `data` | yes | `sessions/`, `memories/`, `skills/`, `logs/`, `home/` — Hermes creates these itself. |
| `/opt/data/SOUL.md` | ConfigMap `hermes-config` key `SOUL.md` | no (subPath mount) | Persona. Not agent-written — Hermes only self-modifies `MEMORY.md` and `skills/`; SOUL.md changes take effect on the *next new session*, no restart needed. |
| `/opt/data/config.yaml` | ConfigMap `hermes-config` key `config.yaml` | no (subPath mount) | Model/provider/MCP-server config. Also operator-authored — `hermes config set` is a human-run CLI command, not something the agent invokes on itself. |

**The `hermes-config` ConfigMap is not a resource in this base** — it's
expected to exist in the profile's namespace by the time the Deployment
starts. The plan is for each profile overlay to produce it from a
`configMapGenerator` targeting profile content that lives in a separate,
private repo (`SOUL.md`/`config.yaml` per profile aren't meant to live in
this public repo) — see the profile overlay's own README for how that's
wired for a given profile.

## Why not `webapp/components/pvc`

That component hardcodes a mount at `/data`; Hermes's image expects
`/opt/data`. Hand-rolling the PVC + volume patches here (like `pihole2`
does for its own non-generic mount needs) was simpler than patching
around the component's fixed path.

## Why not `webapp/components/probes` / `security-context`

Both are generic, parameterized components meant for apps whose health
path/port or `fsGroup` vary per deployment. For Hermes those values are
fixed properties of the image, not the persona, so they're hardcoded
directly in this base's patches — that way profile overlays don't have
to repeat `${healthPath}`/`${healthPort}`/`${fsGroup}` substitution vars
that would never actually change between profiles.
