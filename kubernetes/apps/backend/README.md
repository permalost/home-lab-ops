# backend

Custom backend service. Deployed via a Flux `OCIRepository` sync (`podinfo-sync.yaml`) with a Flagger canary (`podinfo-canary.yaml`) for progressive delivery.

## Configuration

- **Namespace:** `backend`
- Canary analysis is handled by Flagger — see `podinfo-canary.yaml` for the analysis spec (metrics thresholds, step weight, interval).

## Dependencies

Flagger and Linkerd must be running for canary promotions to work.

## Ingress / Endpoints

No ingress defined in this directory — the backend is intended to be consumed internally by the frontend.

## Troubleshooting

- **Canary stuck:** `kubectl describe canary backend -n backend` for Flagger events.
- **Traffic not splitting:** Verify the pod has the Linkerd proxy injected (`linkerd check --proxy -n backend`).
