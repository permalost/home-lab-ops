# webapp

Shared Kustomize base for simple web applications. Provides a reusable `Deployment` + `Service` pattern with an optional `ingress` component.

## Structure

```text
webapp/
├── base/            # Deployment and Service templates
├── components/
│   └── ingress/     # Optional ingress component (include in app overlays that need external access)
├── deployment.yaml  # Default deployment spec
└── service.yaml     # Default service spec
```

## Usage

Other apps (e.g., `homebox`) use this as a Kustomize base:

```yaml
resources:
  - ../webapp/base

components:
  - ../webapp/components/ingress
```

Override image, namespace, labels, and resource limits in the consuming app's kustomization.

## Troubleshooting

- This directory is a base — it is not deployed directly. Issues will surface in the apps that consume it.
