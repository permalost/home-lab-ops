# unpoller

UniFi controller metrics for the VictoriaMetrics stack (`vkms`). Polls the
controller with the read-only audit user and serves Prometheus on `:9130`.

- Credentials: `externalsecret.yaml` copies them from Bitwarden Secrets Manager
  (project `orion-apps`) into the `unpoller-credentials` Secret through the
  `bitwarden-orion` ClusterSecretStore. Keys: `UP_UNIFI_CONTROLLER_0_URL`, `UP_UNIFI_CONTROLLER_0_USER`, `UP_UNIFI_CONTROLLER_0_PASS` —
  the controller URL, audit username and password. Create or rotate by editing the
  `unpoller-UP_UNIFI_CONTROLLER_0_*` secrets in Bitwarden; restart the pod after a
  rotation. See `kubernetes/infrastructure/external-secrets/README.md`.

- vmagent discovers the target through the `VMServiceScrape`; the vkms chart
  sets `selectAllByDefault: true`, so no scrape-config edit is needed.
- Series land under `unifi_*` (`UP_PROMETHEUS_NAMESPACE=unifi`), which the
  WDO-20 Phase 2 alert rules build on.
- InfluxDB output is disabled (`UP_INFLUXDB_DISABLE=true`).
