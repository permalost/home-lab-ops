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

Apps live in `apps/<name>/`; a cluster shell at `clusters/orion/<name>.yaml`
wires one into orion (the "Wired" column). `manyfold/` and `snipe-it/` are
kept from the decommissioned na cluster, pending migration.

| App | Description | Wired into orion? |
|-----|-------------|--------------------|
| actual-budget | Personal budgeting | yes |
| bookorbit | PDF and ebook library | yes |
| external-endpoints | EndpointSlices for off-cluster services | yes |
| firefly | Personal finance manager | yes |
| flow-collector | Network flow collection | yes |
| forgejo | Git forge | yes |
| forgejo-runner | Forgejo CI runners | yes |
| godseye | Live flights, ships, satellites, earthquakes and CCTV on a 3D globe | yes |
| grocy | Grocery & pantry inventory tracking | yes |
| hermes-agents | Hermes agent deployments | yes |
| hermes-dev | Hermes dev instance | yes |
| hermes-hearth | Hermes Hearth | yes |
| hermes-k8s-mcp | Hermes Kubernetes MCP | yes |
| hermes-sage | Hermes Sage | yes |
| home-automation | Mosquitto, Zigbee2MQTT and Home Assistant | yes |
| homebox | Home inventory management | yes |
| manyfold | 3D model library | no |
| netbox | IPAM and DCIM | yes |
| obsidian-livesync | CouchDB sync backend for Obsidian notes | yes |
| paperclip | Paperclip control plane | yes |
| pihole | DNS / ad-block | yes |
| snipe-it | Asset management | yes |
| unpoller | UniFi exporter | yes |
| webapp | Shared base + components (httproute, pvc, tls-cert, linkerd) consumed by the apps above | n/a (library, not standalone) |
