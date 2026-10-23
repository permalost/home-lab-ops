# unpoller

UniFi controller metrics for the VictoriaMetrics stack (`vkms`). Polls the
controller with the read-only audit user and serves Prometheus on `:9130`.

- Credentials: `unpoller-credentials.sops.yaml` (SOPS + age, committed
  encrypted). Keys: `UP_UNIFI_0_URL`, `UP_UNIFI_0_USER`, `UP_UNIFI_0_PASS` —
  the controller URL, audit username and password. Create or rotate with:

  ```bash
  SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
    sops --encrypt --in-place kubernetes/apps/unpoller/unpoller-credentials.sops.yaml
  ```

- vmagent discovers the target through the `VMServiceScrape`; the vkms chart
  sets `selectAllByDefault: true`, so no scrape-config edit is needed.
- Series land under `unifi_*` (`UP_PROMETHEUS_NAMESPACE=unifi`), which the
  WDO-20 Phase 2 alert rules build on.
- InfluxDB output is disabled (`UP_INFLUXDB_DISABLE=true`).
