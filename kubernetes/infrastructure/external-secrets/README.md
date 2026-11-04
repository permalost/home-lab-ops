# External Secrets Operator

Copies secrets from Bitwarden Secrets Manager (cloud) into Kubernetes `Secret`s, so Deployments keep reading plain `Secret` objects. Bitwarden holds the values people and agents rotate; sops keeps the bootstrap secrets. A token rotation becomes an edit in Bitwarden — no PR.

## Configuration

- **Chart:** `external-secrets` (OCI, `oci://ghcr.io/external-secrets/charts`, see `release.yaml` for the pinned version)
- **Namespace:** `external-secrets`
- **Values source:** ConfigMap (`values.yaml` via kustomize `configMapGenerator`)

`values.yaml` enables the `bitwarden-sdk-server` sidecar deployment (pinned `v0.6.0`). The Bitwarden provider in the ESO controller talks to it at `https://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998`; the sdk-server talks to Bitwarden cloud (US region).

The sdk-server serves HTTPS only. `tls.yaml` issues its `bitwarden-tls-certs` Secret from a self-signed `Issuer` in this namespace, and the stores trust it through `caProvider`. The certificate is issued for ten years on purpose: the sdk-server loads it at startup, so a renewal would leave it serving the old, in-memory copy — re-issue by restarting the `bitwarden-sdk-server` deployment if it is ever renewed.

## Stores

Two `ClusterSecretStore`s live in `stores/`, each bound to one Bitwarden project and one machine account:

| Store | Project | Machine account | Usable from |
|---|---|---|---|
| `bitwarden-orion` | `orion-apps` | `eso-orion` | any namespace |
| `bitwarden-paperclip` | `paperclip` | `eso-paperclip` | `paperclip` only (`spec.conditions`) |

Each store reads its machine-account access token from its own Secret (`bitwarden-orion-token` / `bitwarden-paperclip-token`, key `token`) in the `external-secrets` namespace.

## How a store gets its token

The token Secrets are **not** in git until Jon stores them:

```bash
task bitwarden:token ACCOUNT=eso-orion
task bitwarden:token ACCOUNT=eso-paperclip
```

Copy the access token to the clipboard first, or pipe it on stdin (`echo "$TOKEN" | task bitwarden:token ACCOUNT=eso-orion`). The task writes `stores/eso-orion.sops.yaml` / `stores/eso-paperclip.sops.yaml` (SOPS-encrypted with the repo age key) and adds them to `stores/kustomization.yaml`. Commit and push them; the `external-secrets-stores` Kustomization applies them. The tokens are never printed and never appear in a process argument list.

Until both token Secrets exist, the stores report `Ready=False` and the `external-secrets-stores` Kustomization stays unready — that is the expected state, not a fault. It goes green once the tokens are applied.

## Adding a secret

Copy the value into Bitwarden (project matching the store), then reference it by name:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: example
  namespace: paperclip
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-paperclip
    kind: ClusterSecretStore
  target:
    name: example
  data:
    - secretKey: TOKEN
      remoteRef:
        key: example-token
```

UnPoller was the first app moved to Bitwarden (WDO-79 plan phase 4); migrations continue one app per PR (phases 5–6).

## Dependencies

- `cert-manager` — issues the sdk-server certificate.
- `cluster-settings` — Flux substitution source.
- The `sops-age` key decrypts the token Secrets.

## Troubleshooting

- **Store `Ready=False` with a secret-not-found reason:** the token Secret has not been stored yet — run the task above.
- **Store `Ready=False` after a token exists:** check `kubectl get clustersecretstore <name> -o yaml` for the condition message; the token may have been revoked in Bitwarden.
- **sdk-server TLS errors:** `kubectl get certificate -n external-secrets` — if the certificate is not `Ready`, the Issuer failed; `kubectl describe certificate bitwarden-sdk-server -n external-secrets`.
