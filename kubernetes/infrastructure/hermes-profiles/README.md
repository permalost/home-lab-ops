# hermes-profiles source

Wires the private [`permalost/hermes-profiles`](https://github.com/permalost/hermes-profiles)
repo into Flux as a second `GitRepository`, read via a read-only deploy key.

`home-lab-ops` is public; Hermes Agent profile *content* — `SOUL.md`
(persona), `config.yaml` (model/MCP config) — lives in that private repo
instead, one directory per profile. The deployment *mechanism*
(`kubernetes/apps/hermes-agent/base` and per-profile overlays) stays here.

Every profile lands in the same shared `hermes` namespace (see
`kubernetes/apps/hermes-agent/namespace.yaml`), so each profile has two
Flux Kustomizations that both set the *same* `appName` substitution value
to keep a cross-repo reference in sync: the usual one from `sourceRef:
flux-system` builds the Deployment/Service/PVC from this repo (with
`namePrefix: <profile>-` to avoid colliding with other profiles' objects);
a second one with `sourceRef: {kind: GitRepository, name: hermes-profiles}`
runs a `configMapGenerator` (with `disableNameSuffixHash: true`, name
`${appName}-config`) against that profile's directory in the private
repo, producing the ConfigMap the Deployment references by that same
substituted name. See
`kubernetes/apps/hermes-agent/overlays/nas-ops/README.md` for a concrete
example.

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
