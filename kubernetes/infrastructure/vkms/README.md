# vkms (VictoriaMetrics k8s Stack)

Full observability stack: VictoriaMetrics for metrics storage, vmagent for scraping, vmalert for alerting rules, Alertmanager for alert routing, and Grafana for dashboards.

## Configuration

- **Chart:** `vm/victoria-metrics-k8s-stack` (latest)
- **Namespace:** `monitoring`
- **Values source:** ConfigMap (`values.yaml` via kustomize `configMapGenerator`)

Values are managed in `values.yaml` (plain YAML, not inline in the HelmRelease). Kustomize generates a hashed ConfigMap from it so that changing values triggers automatic HelmRelease re-reconciliation.

All five components expose ingress on the `cilium` ingressClass at `<component>.${domain}`. Hostnames are injected at reconciliation time from `cluster-settings.yaml`. Grafana and Alertmanager are homepage-listed under "Cluster" via `gethomepage.dev/*` annotations; the other three aren't.

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

## Alerting

Two receivers match every `warning`/`critical` alert independently
(`continue: true`, neither depends on the other):

- **telegram-hermes** (`alerting/alertmanagerconfig.yaml`, a
  `VMAlertmanagerConfig`) — human paging.
- **webhook-hermes** (`values.yaml`, `alertmanager.config`) — fires
  hermes-hearth's `maintenance` skill. Lives in the base config rather than a
  CR because the operator drops unknown `http_config` keys (e.g.
  `http_headers`) when re-marshaling a CR receiver — an auth header set on a
  `VMAlertmanagerConfig` never goes out. Alertmanager can't compute an HMAC
  either, so auth is a plain `X-Gitlab-Token` header, sourced from
  `alertmanager-hermes` (mounted by `alertmanager.spec.secrets` at
  `/etc/vm/secrets/alertmanager-hermes/token`). That token must stay
  byte-identical to hermes-hearth's `hermesWebhookSecret`
  (`apps/hermes-hearth/secret.yaml`) — checked by
  `scripts/check-webhook-secret-parity.sh`, part of `task gen:validate`.

## Troubleshooting

- **HelmRelease not re-reconciling after values change:** Check that the ConfigMap hash changed (the ConfigMap name should have a new suffix). If not, the kustomizeconfig.yaml `nameReference` transformer may not be applied.
- **Grafana dashboards empty:** vmagent may not be scraping. Check `kubectl -n monitoring logs -l app=vmagent`.
- **Alertmanager not firing:** Verify alert routing config and that vmalert is connecting to vmsingle.

## UniFi alerts

`alerting/unifi-rules.yaml` alerts on the `unifi_*` metrics UnPoller exports
(`apps/unpoller`): controller polling, disconnected/pending APs and switches, WAN
state and latency, PoE budget, port errors, channel utilization, and DHCP pool
utilization. Every rule carries a `severity` and an `owner` label (warning → hobbes,
critical → spiff); routing matches on `severity` only — nothing consumes `owner` yet.
Provisional thresholds (WAN degraded, port errors) were derived from ~1 h of healthy
data on 2026-10-23, not the 5 days the alert plan asked for.

## Gateway HTTPS probe

`alerting/blackbox-exporter.yaml` + `probes/gateway-probes.yaml` probe `https://{git,paperclip,homepage}.${domain}`
from inside the cluster every 30 s (the path the runner and agents use). `alerting/gateway-rules.yaml`:
`GatewayHTTPSDown` (critical, 2 m), `GatewayHTTPSCertExpiringSoon` (warning, served cert < 14 d),
`GatewayProbeMissing` (warning, the probe itself stopped reporting). Critical/warning alerts reach Hearth
and Telegram; the `GatewayHTTPSDown` description is a runbook for Hearth. The probe lives in its own
Kustomization (`vkms-probes`) because it needs `${domain}` substitution, which would mangle the `$labels`
templates in `alerting/`. To add a hostname, add it to `probes/gateway-probes.yaml`.
