# faces

Face recognition/detection service. Deployed with both a Flagger canary (`faces-canary.yaml`) and an A/B test (`faces-abtest.yaml`) for progressive delivery experimentation.

## Configuration

- **Namespace:** `faces`
- Canary and A/B test specs define traffic routing rules; see the respective YAML files for analysis config.

## Dependencies

Flagger and Linkerd must be running for canary/A/B analysis.

## Ingress / Endpoints

Exposed via `faces-ingress.yaml` using the nginx ingress class.

## Troubleshooting

- **A/B test not routing correctly:** Verify Flagger's SMI traffic split is applied (`kubectl get trafficsplit -n faces`).
- **Canary failing analysis:** Check Linkerd Viz metrics for the faces namespace.
