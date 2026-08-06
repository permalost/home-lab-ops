# kubernetes/

Flux-managed in-cluster state for all clusters. Flux is bootstrapped once per cluster (see `bootstrap/`) and then continuously reconciles this directory.

## Structure

```text
kubernetes/
├── bootstrap/        # One-time Flux install kustomization (run once per cluster)
├── clusters/orion/   # Flux entry point for the orion cluster
├── settings/orion/   # cluster-settings ConfigMap + cluster-secrets sops Secret
│                     #   (deliberately outside clusters/orion/ — see below)
├── infrastructure/   # Shared building blocks: CNI, gateway, storage, observability
├── apps/             # Workload deployments (some not yet wired into orion — kept
│                     #   from the decommissioned na cluster pending migration)
└── repos/helm/       # HelmRepository source definitions
```

## How It Works

Each cluster under `clusters/<name>/` contains:
- `flux-system/` — Flux bootstrap components (`gotk-components.yaml`, `gotk-sync.yaml`)
- `cluster-settings.yaml` — the Flux Kustomization CR that reconciles `settings/<name>/`
  (with sops decryption) — not to be confused with `settings/<name>/cluster-settings.yaml`,
  the actual ConfigMap providing cluster-scoped variables (`${domain}`, `${externalIp}`)
- One Kustomization per infrastructure component and app, each pointing at the relevant path in `infrastructure/` or `apps/` with `substituteFrom: cluster-settings`

`clusters/<name>/` has no root `kustomization.yaml` of its own — Flux auto-generates
one by walking the directory, which is why `settings/<name>/` lives *outside*
`clusters/<name>/`: if it were nested inside, the auto-generated root Kustomization
would apply it too, without the sops decryption only the dedicated `cluster-settings`
Kustomization CR has, racing the two on every reconcile.

Flux reconciles `clusters/<name>/` → which creates Kustomizations for each component → which render and apply the manifests in `infrastructure/`, `apps/`, and `settings/<name>/`.

## Variable Substitution

Cluster-specific values (domain, external IP) are injected via Flux's `postBuild.substituteFrom` from `cluster-settings.yaml`. Manifests use `${domain}` and `${externalIp}` as placeholders.

## Adding a New Component

1. Create `kubernetes/infrastructure/<name>/` or `kubernetes/apps/<name>/` with a `kustomization.yaml` and HelmRelease/manifests.
2. Add a Kustomization entry in `kubernetes/clusters/<target-cluster>/<name>.yaml` pointing at the new path.
3. Run `task gen:validate` to confirm the manifests pass kubeconform + kube-linter before committing.

## Infrastructure Components

See [infrastructure/README.md](infrastructure/README.md) for the full component list.

## Apps

Only `pihole2/overlays/orion` is currently wired into the orion cluster. The
rest are kept from the decommissioned na cluster, pending migration.

| App | Description | Wired into orion? |
|-----|-------------|--------------------|
| ai | LiteLLM proxy + Ollama + Open WebUI | no |
| home-automation | Mosquitto + Zigbee2MQTT | no |
| homebox | Home inventory management | no |
| pihole2 | DNS + ad-blocking | yes (`overlays/orion`) |
| webapp | Shared base + components (ingress, httproute, pvc, tls-cert, linkerd) consumed by the apps above | n/a (library, not standalone) |
