# unifi-drift

Weekly audit of the UniFi controller for config drift. The
`unifi-drift-audit` CronJob runs the `wdo/unifi` audit image (see that
repo's README) with `--non-interactive --diff latest` every Monday at
03:00 UTC. Reports live on the `unifi-drift-reports` PVC, mounted at
`/reports`, so each run can diff against the newest earlier one.

The job reuses the read-only audit user from UnPoller: it runs in the
`unpoller` namespace and maps `unpoller-credentials` keys to the
audit image's env. `UNIFI_HOST` is parsed from the URL-shaped
`UP_UNIFI_CONTROLLER_0_URL`; the username and password map directly.

When the diff is non-empty, the job POSTs one `UnifiConfigDrift`
warning alert to Alertmanager (`owner=spiff`), and the alert names the
changed categories. Nothing is sent when nothing changed. A failed run
alerts through `UnifiDriftJobFailed` in `infrastructure/vkms/alerting/`,
plus `UnifiDriftScheduleStalled` if no Job has been scheduled for over
8 days.

## Gotchas

- The image is pulled from the private Forgejo registry with the
  `unifi-drift-registry-pull` Secret (added pre-merge as
  `registry-pull.sops.yaml` in this dir — commands in the PR); without
  it the pods stay in `ImagePullBackOff`.
- The first run writes a baseline report and sends no alert.
- A corrupt newest report fails every later run with exit 2 until the
  file is deleted from the PVC.
