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

## Every profile shares one namespace

All Hermes profiles live in a single `hermes` namespace
(`../namespace.yaml`, its own Flux Kustomization — deliberately not owned
by any one profile, so deleting a profile later doesn't prune the
namespace out from under the others still running in it). That means
**every profile overlay must set a unique `namePrefix`** (e.g.
`nas-ops-`) so the Deployment/Service/PVC this base declares don't
collide with another profile's. `nameReference.yaml` keeps the PVC
volume's `claimName` in sync with that prefix automatically; give the
Secret you add per-profile its final prefixed name directly rather than
relying on kustomize to fix up its `envFrom` reference (unverified
whether that's auto-rewired here — see the `nas-ops` overlay for the
pattern actually in use).

## Volume contract

| Path | Source | Writable | Notes |
|---|---|---|---|
| `/opt/data` | PVC `data` (→ `<prefix>data` per profile) | yes | `sessions/`, `memories/`, `skills/`, `logs/`, `home/` — Hermes creates these itself. |
| `/opt/data/SOUL.md` | ConfigMap `${appName}-config` key `SOUL.md` | no (subPath mount) | Persona. Not agent-written — Hermes only self-modifies `MEMORY.md` and `skills/`; SOUL.md changes take effect on the *next new session*, no restart needed. |
| `/opt/data/config.yaml` | ConfigMap `${appName}-config` key `config.yaml` | no (subPath mount) | Model/provider/MCP-server config. Also operator-authored — `hermes config set` is a human-run CLI command, not something the agent invokes on itself. |

**The `${appName}-config` ConfigMap is not a resource in this base** —
it's expected to exist in the shared namespace, named per-profile, by
the time the Deployment starts. Named per-profile (not a fixed literal
like the container name's `${appName}` alone) precisely because every
profile shares one namespace. It's produced by a second, profile-specific
Flux Kustomization running a `configMapGenerator` against that profile's
directory in the private `hermes-profiles` repo, with the *same*
`appName` substitution value set on both Kustomizations so the names
line up — see the profile overlay's own README for the concrete wiring.

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
