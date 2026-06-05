# frontend

Custom frontend application. Deployed with a Flagger A/B test (`podinfo-abtest.yaml`) and ingress for external access.

## Configuration

- **Namespace:** `frontend`
- A/B test configuration is in `podinfo-abtest.yaml`.

## Dependencies

Flagger and Linkerd for A/B traffic routing.

## Ingress / Endpoints

Exposed via `podinfo-ingress.yaml` using the nginx ingress class.

## Troubleshooting

- **A/B test not activating:** Verify the header/cookie routing rules in `podinfo-abtest.yaml` and that Linkerd is meshing the namespace.
