# webapp — shared Kustomize base

Reusable building blocks for simple web apps. Consuming apps pull `webapp/base` as a resource base and opt into Components for ingress, persistent storage, service-mesh injection, and TLS.

## Structure

```text
webapp/
├── base/
│   ├── deployment.yaml   # Deployment named "deploy"; container name = ${appName}, image = my-app, port 8080
│   └── service.yaml      # Service named "svc", ClusterIP, port 8080 (name: http)
└── components/
    ├── ingress/          # nginx Ingress + cert-manager TLS at ${subdomain}.${domain} (na cluster)
    ├── httproute/        # Gateway API HTTPRoute attached to the orion Gateway (orion cluster)
    ├── pvc/              # ReadWriteOnce PVC + mounts at /data
    ├── tls-cert/         # cert-manager Certificate (for non-ingress TLS scenarios)
    ├── linkerd-inject/   # opt-in Linkerd sidecar injection on the pod template
    └── linkerd-disable/  # explicit Linkerd sidecar opt-out on the pod template
```

## Minimal consumer

```yaml
# kubernetes/apps/my-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../webapp/base

components:
  - ../webapp/components/ingress

namespace: my-service
namePrefix: my-service-

labels:
  - includeSelectors: true
    pairs:
      app: my-service

images:
  - name: my-app
    newName: ghcr.io/example/my-service
    newTag: "1.2.3"
```

Then add a cluster shell at `kubernetes/clusters/orion/my-service.yaml` via `task gen:new-app` or by copying `kubernetes/clusters/_template/app.yaml.tmpl`.

## Component reference

### ingress

Adds an nginx `Ingress` with cert-manager TLS. Use on the **na** cluster (nginx deployed).

| Substitution var | Where to set | Example |
|---|---|---|
| `subdomain` | cluster shell `postBuild.substitute` | `homebox` |
| `domain` | `cluster-settings` ConfigMap | `norseamerican.com` |

### httproute

Adds a Gateway API `HTTPRoute` attached to the `orion` Gateway (ns `gateway`, HTTPS listener). TLS is handled by the wildcard cert at the Gateway — no per-app Certificate needed. Also labels the app namespace with `gateway.networking.k8s.io/access: "true"` so the Gateway permits route attachment. Use on the **orion** cluster.

| Substitution var | Where to set | Example |
|---|---|---|
| `subdomain` | cluster shell `postBuild.substitute` | `dns` |
| `domain` | `cluster-settings` ConfigMap | `orion.norseamerican.com` |

### pvc

Adds a `ReadWriteOnce` PVC named `data` and mounts it at `/data` on the `deploy` container. A `nameReference` transformer rewires the volume's `claimName` when `namePrefix` is applied. The volumeMount patch targets `spec.template.spec.containers/0` — the first container in the Deployment.

| Substitution var | Where to set | Example |
|---|---|---|
| `storageClass` | cluster shell `postBuild.substitute` | `longhorn` |
| `storageSize` | cluster shell `postBuild.substitute` | `5Gi` |

### tls-cert

Adds a cert-manager `Certificate` for `${subdomain}.${domain}` using the `letsencrypt-prod` ClusterIssuer. Useful when you need a TLS secret without an nginx Ingress (e.g. Cilium Gateway, gRPC, direct TLS).

Uses the same `subdomain` / `domain` substitution vars as `ingress`. Requires the `letsencrypt-prod` ClusterIssuer to exist; the certificate secret is written to `${subdomain}-${domain}-tls`.

### linkerd-inject / linkerd-disable

Patches `spec.template.metadata.annotations` on the `deploy` Deployment to opt the pod in or out of Linkerd sidecar injection. Include at most one per overlay.

No substitution vars required.

## Generating a new app

```bash
task gen:new-app NAME=my-service SUBDOMAIN=my-service IMAGE=ghcr.io/example/my-service:latest
```

This writes `kubernetes/apps/my-service/kustomization.yaml` and `kubernetes/clusters/orion/my-service.yaml`. Edit them, then run `task gen:validate`.

## Handling secrets

Per-app secrets live at `kubernetes/apps/<app-name>/secret.sops.yaml` (one file per app, distinct from cluster-wide secrets in `settings/cluster-secrets.sops.yaml`). Add one like this:

```bash
# create the plaintext secret
cat > kubernetes/apps/my-service/secret.sops.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-service-secret
  namespace: my-service
stringData:
  api-key: "replace-me"
EOF

# encrypt in-place (SOPS_AGE_KEY_FILE must point to your age key)
sops --encrypt --in-place kubernetes/apps/my-service/secret.sops.yaml

# add to resources in kustomization.yaml
```

The cluster shell already includes `decryption: { provider: sops, secretRef: { name: sops-age } }`.

## Notes

- `webapp/base` and `webapp/components/` are excluded from direct `kustomize build` validation in `scripts/validate.sh` — they are not standalone overlays.
- `apps/homebox/` is the canonical real-world example of a consumer.
