# hermes-agent/base — the only thing a Hermes profile needs, here

There is deliberately no `kubernetes/apps/hermes-agent/overlays/<profile>/`
anymore. Every profile-specific value is a Flux `postBuild.substitute`
token (`appName`, `subdomain`, `storageClass`, `storageSize`), and every
profile's own Flux `Kustomization` — defined and applied from the private
[`hermes-profiles`](../../../infrastructure/hermes-profiles/README.md)
repo, not here — points straight at this base with its own substitution
values. Adding a profile touches this repo exactly once, ever: the
bootstrap Kustomization at `kubernetes/clusters/orion/hermes-profiles-bootstrap.yaml`.

Like `webapp/base`, this base contains the unresolved `${appName}` token
and is excluded from full build/lint validation in `scripts/validate.sh`
(which does run a plain structural `kustomize build` against it — no
Kustomization in this repo exercises it end-to-end anymore, since the
Kustomizations that do now live in `hermes-profiles`).

Fixes everything common to every profile: the `nousresearch/hermes-agent`
image, gateway (8642) + dashboard (9119) ports, the dashboard exposed via
`httproute` on port 80 (matching the component's hardcoded backend port,
same workaround `pihole2` uses), health probes, default resource sizing,
and the volume layout below.

## Every profile shares one namespace

All Hermes profiles live in a single `hermes` namespace
(`../namespace.yaml`, its own Flux Kustomization — deliberately not owned
by any one profile, so deleting a profile later doesn't prune the
namespace out from under the others still running in it). `namePrefix:
${appName}-` (set directly in this base) is what keeps profiles from
colliding — Flux's `postBuild.substitute` is a raw string replacement
over the *fully-rendered* manifest, so a templated `namePrefix` resolves
exactly like any other substituted field, and `nameReference.yaml` keeps
the PVC volume's `claimName` in sync with it. Verified end-to-end: build
this base, hand-substitute `appName=nas-ops` (simulating what Flux does),
and every name-reference (PVC claimName, ConfigMap/Secret references,
HTTPRoute backendRef) lines up and validates against real Kubernetes
schemas.

## Structural differences (sidecars, extra volumes) don't need a change here either

A profile needing something beyond this base's generic contract — e.g.
`nas-ops`'s TrueNAS MCP sidecar containers — adds it via `spec.patches`
on that profile's *own* Flux `Kustomization` object (JSON6902/strategic-merge,
applied after this base builds, targeted by kind/name/labelSelector — a
real Flux feature, not a Kustomize-level hack). That patch lives in
`hermes-profiles`, not here. This base only needs to change if a future
need can't be expressed as a patch against its output at all — a much
higher bar than "needs a sidecar."

## Volume contract

| Path | Source | Writable | Notes |
|---|---|---|---|
| `/opt/data` | PVC `${appName}-data` | yes | `sessions/`, `memories/`, `skills/`, `logs/`, `home/` — Hermes creates these itself. |
| `/opt/data/SOUL.md` | ConfigMap `${appName}-config` key `SOUL.md` | no (subPath mount) | Persona. Not agent-written — Hermes only self-modifies `MEMORY.md` and `skills/`; SOUL.md changes take effect on the *next new session*, no restart needed. |
| `/opt/data/config.yaml` | ConfigMap `${appName}-config` key `config.yaml` | no (subPath mount) | Model/provider/MCP-server config. Also operator-authored — `hermes config set` is a human-run CLI command, not something the agent invokes on itself. |

Also expected, by the same `${appName}-<suffix>` convention: a Secret
named `${appName}-secrets`, injected wholesale via `envFrom` (used for
API keys, e.g. TrueNAS credentials for `nas-ops`). Neither the ConfigMap
nor the Secret is a resource in this base — both are produced by the
profile's own content in `hermes-profiles`, in the same Kustomization,
with `postBuild.substitute.appName` set to the same value used here so
the names agree.

## Why not `webapp/components/pvc`

That component hardcodes a mount at `/data`; Hermes's image expects
`/opt/data`. Hand-rolling the PVC + volume patches here (like `pihole2`
does for its own non-generic mount needs) was simpler than patching
around the component's fixed path.

## Why not `webapp/components/probes` / `security-context`

Both are generic, parameterized components meant for apps whose health
path/port or `fsGroup` vary per deployment. For Hermes those values are
fixed properties of the image, not the persona, so they're hardcoded
directly in this base's patches — one less thing every profile would
otherwise have to set identically.
