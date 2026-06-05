# linkerd

Service mesh providing automatic mTLS between meshed pods, traffic observability via Linkerd Viz, and SMI support.

## Configuration

Components installed:
- `linkerd-crds` — CRD-only chart, applied first
- `linkerd-control-plane` — core control plane
- `linkerd-smi` — SMI adaptor (used by Flagger)
- `linkerd-viz` — Prometheus + dashboard

Trust anchor certificates are stored in `secret.yaml` (SOPS-encrypted).

## Dependencies

cert-manager is not required — Linkerd manages its own certificates. Flagger depends on Linkerd being ready if `meshProvider: linkerd` is set.

## Ingress / Endpoints

Linkerd Viz dashboard is exposed via ingress (`ingress.yaml`).

## Certificate Generation

Generate a new trust anchor (valid 10 years) and issuer certificate (valid 1 year):

```sh
task link:create-certs
```

The generated certs must be SOPS-encrypted before committing:

```sh
sops -e -i kubernetes/infrastructure/linkerd/secret.yaml
```

Certificates expire — rotate the issuer cert annually.

## Troubleshooting

- **Pods not meshed:** Add `linkerd.io/inject: enabled` annotation to the namespace or pod spec.
- **mTLS errors:** Run `linkerd check` to verify the control plane is healthy.
- **Viz dashboard inaccessible:** Check `kubectl -n linkerd-viz get pods` and the ingress resource.
