# vkms (VictoriaMetrics k8s Stack)

Full observability stack: VictoriaMetrics for metrics storage, vmagent for scraping, vmalert for alerting rules, Alertmanager for alert routing, and Grafana for dashboards.

## Configuration

- **Chart:** `vm/victoria-metrics-k8s-stack` (latest)
- **Namespace:** `monitoring`
- **Values source:** ConfigMap (`values.yaml` via kustomize `configMapGenerator`)

Values are managed in `values.yaml` (plain YAML, not inline in the HelmRelease). Kustomize generates a hashed ConfigMap from it so that changing values triggers automatic HelmRelease re-reconciliation.

All five components expose ingress on the `cilium` ingressClass at `<component>.${domain}`. Hostnames are injected at reconciliation time from `cluster-settings.yaml`.

## Dependencies

Cilium must be running (provides the ingress class). cert-manager is optional but recommended for TLS on the ingress endpoints.

## Ingress / Endpoints

| Component | Host |
|-----------|------|
| Grafana | `grafana.${domain}` |
| Alertmanager | `alertmanager.${domain}` |
| vmagent | `vmagent.${domain}` |
| vmalert | `vmalert.${domain}` |
| vmsingle | `vmsingle.${domain}` |

## Troubleshooting

- **HelmRelease not re-reconciling after values change:** Check that the ConfigMap hash changed (the ConfigMap name should have a new suffix). If not, the kustomizeconfig.yaml `nameReference` transformer may not be applied.
- **Grafana dashboards empty:** vmagent may not be scraping. Check `kubectl -n monitoring logs -l app=vmagent`.
- **Alertmanager not firing:** Verify alert routing config and that vmalert is connecting to vmsingle.
