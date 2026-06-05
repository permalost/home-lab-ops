# kubernetes/

Flux-managed in-cluster state for all clusters. Flux is bootstrapped once per cluster (see `bootstrap/`) and then continuously reconciles this directory.

## Structure

```text
kubernetes/
├── bootstrap/        # One-time Flux install kustomization (run once per cluster)
├── clusters/         # Per-cluster Flux entry points
│   ├── orion/        # Talos cluster (active)
│   └── na/           # k3s cluster (active, being replaced by orion)
├── infrastructure/   # Shared building blocks: CNI, ingress, storage, observability
├── apps/             # Workload deployments
└── repos/helm/       # HelmRepository source definitions
```

## How It Works

Each cluster under `clusters/<name>/` contains:
- `flux-system/` — Flux bootstrap components (`gotk-components.yaml`, `gotk-sync.yaml`)
- `cluster-settings.yaml` — ConfigMap providing cluster-scoped variables (`${domain}`, `${externalIp}`)
- One Kustomization per infrastructure component and app, each pointing at the relevant path in `infrastructure/` or `apps/` with `substituteFrom: cluster-settings`

Flux reconciles `clusters/<name>/` → which creates Kustomizations for each component → which render and apply the manifests in `infrastructure/` and `apps/`.

## Variable Substitution

Cluster-specific values (domain, external IP) are injected via Flux's `postBuild.substituteFrom` from `cluster-settings.yaml`. Manifests use `${domain}` and `${externalIp}` as placeholders.

## Adding a New Component

1. Create `kubernetes/infrastructure/<name>/` or `kubernetes/apps/<name>/` with a `kustomization.yaml` and HelmRelease/manifests.
2. Add a Kustomization entry in `kubernetes/clusters/<target-cluster>/<name>.yaml` pointing at the new path.
3. Run `task gen:validate` to confirm the manifests pass kubeconform + kube-linter before committing.

## Infrastructure Components

See [infrastructure/README.md](infrastructure/README.md) for the full component list.

## Apps

| App | Description |
|-----|-------------|
| ai | LiteLLM proxy + Ollama + Open WebUI |
| backend | Custom backend service |
| faces | Face recognition service |
| frontend | Custom frontend |
| home-automation | Home Assistant / MQTT stack |
| homebox | Home inventory management |
| pihole | Primary DNS + ad-blocking |
| pihole2 | Secondary DNS (HA pair) |
| plans | Planning/notes app |
| webapp | Custom web application |
