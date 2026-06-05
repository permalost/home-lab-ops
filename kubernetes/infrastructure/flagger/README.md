# flagger

Progressive delivery operator — automates canary releases and A/B tests using traffic weights. Integrates with Linkerd as the mesh provider.

## Configuration

- **Chart:** `flagger/flagger` (1.x, latest minor)
- **Namespace:** `flagger-system`
- **Values source:** HelmRelease inline

Key config:
- `meshProvider: linkerd` — uses Linkerd for traffic splitting
- `metricsServer: http://prometheus.linkerd-viz:9090` — pulls metrics from Linkerd Viz Prometheus

A load tester is deployed alongside (`loadtester.yaml`) to generate traffic during canary analysis.

## Dependencies

Linkerd must be installed and meshing the target namespaces. Linkerd Viz Prometheus must be running for metrics-based canary analysis.

## Ingress / Endpoints

No direct ingress. Flagger creates and manages canary/primary Service objects per `Canary` CR.

## Troubleshooting

- **Canary stuck in `Progressing`:** Check `kubectl describe canary <name> -n <ns>` for events. Often a metrics query timeout or load tester unreachable.
- **Traffic split not working:** Verify the target pod is meshed with Linkerd (`linkerd check --proxy -n <ns>`).
