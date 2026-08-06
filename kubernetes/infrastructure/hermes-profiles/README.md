# hermes-profiles source

Wires the private [`permalost/hermes-profiles`](https://github.com/permalost/hermes-profiles)
repo into Flux as a second `GitRepository`, read via a read-only deploy key.

`home-lab-ops` is public; Hermes Agent profile *content* — persona, config,
secrets, and each profile's own Flux wiring — lives in that private repo
instead. The deployment *mechanism* (`kubernetes/apps/hermes-agent/base`)
stays here, and stays generic: adding a profile never touches this repo.

## How a profile actually gets deployed

One Kustomization here, `kubernetes/clusters/orion/hermes-profiles-bootstrap.yaml`,
is sourced from this `GitRepository` at `path: ./flux` and never changes.
Its build output is a set of *more* Flux `Kustomization` objects — one
pair per profile — which is a supported Flux pattern (a Kustomization's
output can legitimately include more Kustomization/GitRepository
resources; we already do a version of this, since this very `GitRepository`
is itself emitted from a `home-lab-ops`-sourced Kustomization).

Each profile's pair, defined entirely in `hermes-profiles:/flux/<profile>.yaml`:

1. A **content** Kustomization, `sourceRef: {kind: GitRepository, name:
   hermes-profiles}`, `path: ./<profile>` — runs a `configMapGenerator`
   (name `${appName}-config`, `disableNameSuffixHash: true`) and applies
   that profile's `secret.sops.yaml` (name `${appName}-secrets`),
   decrypted with the same in-cluster `sops-age` key `home-lab-ops` uses —
   decryption is a property of the Kustomization spec, not the source
   repo, so this works identically regardless of which repo holds the
   ciphertext.
2. A **deploy** Kustomization, `sourceRef: flux-system`, `path:
   ./kubernetes/apps/hermes-agent/base` (in `home-lab-ops` — unchanging,
   shared by every profile), with `postBuild.substitute: {appName:
   <profile>, subdomain: ..., storageClass: ..., storageSize: ...}`. Any
   structural need beyond the generic base (extra sidecars, extra
   volumes) is a `spec.patches` block on *this* Kustomization —
   JSON6902/strategic-merge, applied after the base builds — not a
   change to `hermes-agent/base` itself.

Both Kustomizations set the same `appName` so the content Kustomization's
`${appName}-config`/`${appName}-secrets` and the deploy Kustomization's
references to them agree.

**Adding a new profile touches nothing in `home-lab-ops`** — just a new
directory + a new `flux/<profile>.yaml` pair, both in this repo. See
`nas-ops/` for the concrete example.

## CI coverage note

`home-lab-ops`'s `task test:build-all` can no longer exercise
`hermes-agent/base` end-to-end with real substituted values — it only
scans `kubernetes/clusters/<cluster>/*.yaml`, and the Kustomizations that
do that now live here. `home-lab-ops` keeps a structural-only safety net
(`kustomize build` with no substitution, in `scripts/validate.sh`). Full
profile-level validation only happens by testing against this repo
directly — it doesn't have its own CI yet; a fast follow, not yet built.

## Deploy key

Generated locally (not derived from any existing repo key) and registered
as a **read-only** deploy key on the private repo:

```sh
ssh-keygen -t ed25519 -N "" -f identity -C "flux-orion-readonly@hermes-profiles"
gh repo deploy-key add identity.pub --repo permalost/hermes-profiles --title "flux-orion-readonly"
```

`secret.sops.yaml` holds the private half plus `known_hosts` for
`github.com`, SOPS-encrypted the same way every other secret in this repo
is. Rotate by generating a new keypair, replacing the deploy key on GitHub,
and re-encrypting.
