# kubernetes/

Flux-managed in-cluster state for all clusters. Flux is bootstrapped once per cluster (see `bootstrap/`) and then continuously reconciles this directory.

## Structure

```text
kubernetes/
├── bootstrap/        # One-time Flux install kustomization (run once per cluster)
├── clusters/orion/   # Flux entry point for the orion cluster
├── settings/orion/   # cluster-settings ConfigMap + cluster-secrets sops Secret
├── infrastructure/   # Shared building blocks: CNI, gateway, storage, observability
├── apps/             # Workload deployments (some not yet wired into orion — kept
│                     #   from the decommissioned na cluster pending migration)
└── repos/helm/       # HelmRepository source definitions
```

## How It Works

Each cluster under `clusters/<name>/` contains:
- `flux-system/` — Flux bootstrap components (`gotk-components.yaml`, `gotk-sync.yaml`)
- `cluster-settings.yaml` — the Flux Kustomization CR (sops decryption) reconciling
  `settings/<name>/`, where the actual ConfigMap/Secret live
- One Kustomization per infrastructure component and app, `substituteFrom: cluster-settings`

`clusters/<name>/` has no root `kustomization.yaml` — Flux auto-generates one by
walking the directory. `settings/<name>/` lives outside `clusters/<name>/` so that
walk (no decryption config) can't apply it racing the dedicated Kustomization that does.

Flux reconciles `clusters/<name>/` → Kustomizations per component → manifests in
`infrastructure/`, `apps/`, and `settings/<name>/`.

## Variable Substitution

Cluster-specific values (domain, external IP) are injected via Flux's `postBuild.substituteFrom` from `cluster-settings.yaml`. Manifests use `${domain}` and `${externalIp}` as placeholders.

## Adding a New Component

1. Create `kubernetes/infrastructure/<name>/` or `kubernetes/apps/<name>/` with a `kustomization.yaml` and HelmRelease/manifests.
2. Add a Kustomization entry in `kubernetes/clusters/<target-cluster>/<name>.yaml` pointing at the new path.
3. Run `task gen:validate` to confirm the manifests pass kubeconform + kube-linter before committing.

## Infrastructure Components

See [infrastructure/README.md](infrastructure/README.md) for the full component list.

## Apps

Only `pihole/overlays/orion` is currently wired into the orion cluster. The
rest are kept from the decommissioned na cluster, pending migration.

| App | Description | Wired into orion? |
|-----|-------------|--------------------|
| ai | LiteLLM proxy + Ollama + Open WebUI | no |
| home-automation | Mosquitto + Zigbee2MQTT | no |
| homebox | Home inventory management | no |
| pihole | DNS + ad-blocking | yes (`overlays/orion`) |
| webapp | Shared base + components (ingress, httproute, pvc, tls-cert, linkerd) consumed by the apps above | n/a (library, not standalone) |
