# netbox

[NetBox](https://github.com/netbox-community/netbox) — IPAM and DCIM
(netbox-docker 5.1.1 packaging, NetBox 4.7.3). Four workloads in one
namespace, so this app is plain manifests rather than the `webapp` base
(which covers a single Deployment + Service + HTTPRoute):

- **netbox** — web frontend. The image entrypoint waits for the DB, applies
  migrations, seeds the superuser from `netbox-secret`, then serves via
  granian on 8080. No separate migration Job.
- **netbox-worker** — same image, `manage.py rqworker` (all queues), mirroring
  netbox-docker's compose override. Runs with `SKIP_SUPERUSER: "true"`.
- **netbox-valkey** — Valkey 8.1 with no persistence: tasks (db 0) and cache
  (db 1). Losing it only re-runs queued jobs.
- **netbox-db** — CloudNativePG `Cluster` (1 instance, 5Gi
  `rook-ceph-block`), pinned to the same post-eMudhra-fix image as
  `paperclip-db`/`forgejo-db`. Its `netbox-db-app` Secret feeds the `DB_*`
  env on both Deployments (keys `host`, `port`, `dbname`, `user`, `password`).

## Configuration

- **Namespace:** `netbox`
- **Secret:** `netbox-secret` (SOPS, `netbox-secret.sops.yaml`) supplies
  `SECRET_KEY`, `SUPERUSER_NAME`, `SUPERUSER_EMAIL`, `SUPERUSER_PASSWORD`
  (values provided out-of-band; see the WDO-106 rotation runbook).
- **Media:** `netbox-media` PVC (1Gi, `rook-ceph-block`, RWO) mounted at
  `/opt/netbox/netbox/media` on the web pod only. The image ships user
  `netbox` (uid 999, gid 0); `fsGroup: 0` matches its group-writable media
  convention on a fresh volume.
- **Probes:** `/login/` with an explicit `Host: netbox.${domain}` header —
  Django 400s the kubelet's default Host, and the header must be in
  `ALLOWED_HOSTS`. A startupProbe gives first-boot migrations room before
  liveness starts failing the pod.

## First boot

Expect a few `CrashLoopBackOff`s on the web pod until `netbox-db` finishes
initializing — the entrypoint only waits ~30s for the DB before exiting.
Once the Cluster is Ready the pod converges and migrations apply. The
superuser is created from `netbox-secret` on that first successful start.

## Ingress / Endpoints

`netbox.${domain}` via Gateway API. gethomepage.dev annotations surface it
under the "Network" group (added to the Homepage layout in this same change).

## Troubleshooting

- **Web pod restart loop on boot:** `netbox-db` not Ready yet — check
  `kubectl get cluster -n netbox` and wait for `netbox-db-1`.
- **502 from the gateway:** the Service only selects
  `app.kubernetes.io/component: web`, so worker pods can't receive traffic;
  if the route still 502s, check readiness on the web pod.
- **Worker not processing jobs:** confirm `netbox-valkey` is reachable
  (`kubectl exec -n netbox deploy/netbox-worker -- /opt/netbox/venv/bin/python
  /opt/netbox/netbox/manage.py rqcheck`).
