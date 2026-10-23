# Adding services to the orion cluster

Two pathways depending on whether the service ships as a Helm chart or raw manifests.

## Pathway A: Helm chart (infrastructure component)

Use this for cluster-level infrastructure: CNI, ingress, cert-manager, metrics stack, storage drivers.

**Reference implementation:** `kubernetes/infrastructure/cilium/`

1. Create `kubernetes/infrastructure/<name>/` with:
   - `namespace.yaml` — Namespace resource
   - `repository.yaml` — HelmRepository (OCI or HTTP)
   - `release.yaml` — HelmRelease with `valuesFrom: ConfigMap` (not inline `spec.values`)
   - `values.yaml` — Helm values (plain YAML)
   - `kustomization.yaml` — includes `configMapGenerator` from `values.yaml` + `configurations: [kustomizeconfig.yaml]`
   - `kustomizeconfig.yaml` — `nameReference` wiring ConfigMap → HelmRelease `spec/valuesFrom/name`
   - `README.md`

2. Add a cluster shell at `kubernetes/clusters/orion/<name>.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <name>
  namespace: flux-system
spec:
  interval: 10m
  retryInterval: 30s
  timeout: 15m
  prune: true
  wait: true
  dependsOn:
    - name: cluster-settings
    # add more dependsOn here (e.g. cilium, cert-manager)
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/infrastructure/<name>
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-settings
      - kind: Secret
        name: cluster-secrets
```

3. Run `task gen:validate`.

**Why the ConfigMap pattern?** Changing `values.yaml` updates the ConfigMap hash (via `configMapGenerator`), which Flux detects as a drift and triggers a HelmRelease re-reconciliation automatically. Inline `spec.values` changes are also detected, but the ConfigMap approach keeps values in a dedicated file that is easier to diff and review.

---

## Pathway B: Raw manifests / simple web app

Use this for application workloads that follow the standard Deployment + Service + HTTPRoute shape (Gateway API; orion has no nginx ingress controller).

**Reference implementation:** `kubernetes/apps/homebox/`

Headless workloads that don't need a route (exporters, operators) skip `webapp` entirely — copy `apps/unpoller/` instead, the minimal standalone example. `apps/paperclip/` is too big for that role.

### Scaffold with new-app

```bash
task gen:new-app NAME=my-service SUBDOMAIN=my-service IMAGE=ghcr.io/example/my-service:latest
```

This generates:
- `kubernetes/apps/my-service/kustomization.yaml` — pulls `webapp/base`, opts into the `httproute` Component, pre-fills substitution variables
- `kubernetes/clusters/orion/my-service.yaml` — Flux Kustomization shell with `dependsOn: cluster-settings`, sops decryption, and `postBuild.substitute`

### Components available

| Component | What it adds | Required substitute vars |
|---|---|---|
| `httproute` | Gateway API HTTPRoute on `${gatewayName}` (default) | `subdomain`, `domain` and `gatewayName` (from cluster-settings) |
| `pvc` | PVC + /data mount | `storageClass`, `storageSize` |
| `tls-cert` | cert-manager Certificate | `subdomain`, `domain` |
| `ingress` | nginx Ingress; dormant, orion has no nginx | — |
| `linkerd-*` | Linkerd injection; dormant, orion has no Linkerd | — |

Components live at `kubernetes/apps/webapp/components/`. Add them to the `components:` list in your `kustomization.yaml`. See `kubernetes/apps/webapp/README.md` for the full reference.

### Manual steps after scaffolding

1. **Set the correct image tag** — the scaffold uses `latest`; pin to a real tag.
2. **Adjust port if not 8080** — add an inline JSON patch to `kustomization.yaml`:
   ```yaml
   patches:
     - target: {kind: Deployment, name: deploy}
       patch: |-
         - op: replace
           path: /spec/template/spec/containers/0/ports/0/containerPort
           value: 3000
     - target: {kind: Service, name: svc}
       patch: |-
         - op: replace
           path: /spec/ports/0/port
           value: 3000
   ```
3. **Add extra resources** — PVCs not covered by the `pvc` Component, ConfigMaps for env files via `configMapGenerator`, etc.
4. **Add secrets** (see below).
5. **Add `namespace.yaml`** (a `Namespace` named after the app) to `resources:`; the `httproute` component labels it for gateway access. Examples: `apps/grocy/`, `apps/obsidian-livesync/`.
6. **Tag the HTTPRoute for Homepage** with a patch like `apps/obsidian-livesync/patches/httproute-add-homepage-annotations.yaml`. `gethomepage.dev/enabled` must be `"true"` or `"false"`, and `gethomepage.dev/group` must be a group in `infrastructure/homepage/values.yaml` (`task test:build` fails otherwise).
7. **Set `dependsOn`** in the cluster shell to what the app needs (`cilium`, `gateway`, `cert-manager-issuers`, `cluster-settings`); copy `clusters/orion/obsidian-livesync.yaml`.
8. Run `task gen:validate` and `task test:build`. `test:build` renders every Kustomization with substitution; an unresolved `${...}` is a bug.

Do not add a root `kustomization.yaml` under `kubernetes/clusters/orion/`; Flux picks up each shell on its own.

---

## Adding secrets

Secrets must be SOPS-encrypted before committing. `.sops.yaml` matches by filename (`*.sops.yaml`, `secret.yaml`, `configMap.yaml`), so a differently named secret file is committed in plaintext. Per-app secret files can use any `<app>-*.sops.yaml` name (e.g. `my-service-credentials.sops.yaml` — the same pattern as `forgejo-tokens.sops.yaml` and `unpoller-credentials.sops.yaml`). The cluster already has a `cluster-secrets` Secret in `flux-system` for cluster-wide substitution vars. For per-service secrets:

```bash
# 1. Create plaintext
cat > kubernetes/apps/my-service/my-service-credentials.sops.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-service-credentials
  namespace: my-service
stringData:
  api-key: "replace-me"
EOF

# 2. Encrypt in-place
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops --encrypt --in-place kubernetes/apps/my-service/my-service-credentials.sops.yaml

# 3. Add to resources in kustomization.yaml
#    - my-service-credentials.sops.yaml
```

The cluster shell already sets `decryption: { provider: sops, secretRef: { name: sops-age } }` so Flux will decrypt it automatically.

For cluster-wide secrets (values substituted via `${var}` in any service), add the key to `kubernetes/settings/orion/cluster-secrets.sops.yaml`:

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops kubernetes/settings/orion/cluster-secrets.sops.yaml
# edit in the sops-opened editor, save, exit — it re-encrypts automatically
```

---

## Bootstrap order for orion

```text
cluster-settings  (Flux Kustomization at clusters/orion/cluster-settings.yaml)
  └── cilium       (CNI; dependsOn: cluster-settings)
        └── cert-manager   (add when needed; dependsOn: cilium)
              └── <apps>   (dependsOn: cert-manager for TLS, or cilium for basic ingress)
```

Set `dependsOn` in each cluster shell to enforce this. The `task gen:new-app` scaffold defaults to `dependsOn: cluster-settings` — update it for services that need cert-manager or an ingress controller first.

---

## Validation

```bash
# Full kubeconform + kube-linter sweep
task gen:validate

# Build a single overlay to check substitution rendering
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/my-service/
```

No CI decryption of SOPS files — CI schema-validates only. Local `sops -d` with your age key to confirm decryption works.
