# home-lab-ops

GitOps repo for the `orion` homelab cluster (Talos + Flux). Public: no IPs, internal hostnames or alert details in commits, PRs or docs.

## Layers

- `clusters/orion/`: Talos provisioning (talhelper). Never touched by app work.
- `kubernetes/`: Flux-managed state. Flux chain: `GitRepository/flux-system` → `kubernetes/clusters/orion/*.yaml` (one Flux `Kustomization` per app) → `kubernetes/apps/<x>` or `kubernetes/infrastructure/<x>`.
- Substitution comes from `ConfigMap/cluster-settings` and `Secret/cluster-secrets` (`kubernetes/settings/orion/`) via `postBuild.substituteFrom`.
- Routing is Gateway API (`Gateway/orion`), not Ingress.

## Rules

- All changes go through a PR; Flux applies them after merge. `kubectl` is read-only. Never `apply`, `edit`, `delete` or `rollout` by hand.
- Before pushing: `task gen:validate` and `task test:build`. An unresolved `${...}` in `test:build` is a regression.
- Pin image and chart versions. No `latest`.

## Traps

- `.sops.yaml` matches by filename (`*.sops.yaml`, `secret.yaml`, `configMap.yaml`). A secret in any other filename is committed in plaintext. Never commit a plaintext secret.
- `kubernetes/clusters/orion/` has no root `kustomization.yaml`, on purpose. Don't add one, and keep sops-encrypted files out of that directory.
- `kubernetes/clusters/orion/cluster-settings.yaml` is the Flux Kustomization; the ConfigMap it applies is `kubernetes/settings/orion/cluster-settings.yaml`.
- HelmReleases use `values.yaml` + `configMapGenerator` + `kustomizeconfig.yaml` (see `kubernetes/infrastructure/cilium/`), with the `HelmRepository` beside the release.
- Every HTTPRoute needs `gethomepage.dev/enabled` (`"true"`/`"false"`), and its `gethomepage.dev/group` must exist in `kubernetes/infrastructure/homepage/values.yaml`.

## Tasks

- Add a service: `kubernetes/clusters/orion/docs/adding-services.md`. Scaffold with `task gen:new-app NAME= SUBDOMAIN= IMAGE=`.
- Troubleshoot a service: `kubernetes/clusters/orion/docs/troubleshooting.md`.
- Offline render: `task test:build`. Schema and lint: `task gen:validate`.
