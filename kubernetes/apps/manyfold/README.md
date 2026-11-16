# manyfold

[Manyfold](https://github.com/manyfold3d/manyfold) — 3D model and print file
library with scanning, previews and geometric analysis. Built on
`webapp/base` with the `httproute` and `pvc` components.

## Configuration

- **Namespace:** `manyfold`.
- Image `ghcr.io/manyfold3d/manyfold:0.154.1`, pinned by digest (GHCR tags
  carry no `v` prefix). Container listens on `3214` (the image's `PORT`
  default); the `replacements` block in `app/kustomization.yaml` keeps the
  Service port and HTTPRoute backendRef in sync.
- The `manyfold` image (not `manyfold-solo`) needs a separate Postgres and
  Redis, matching upstream's standard docker-compose: one app container
  (foreman supervises the upstream Procfile — rails web + two Sidekiq
  workers — so there is no separate worker Deployment), a CNPG `Cluster`
  (`manyfold-db`, 1 instance, 5Gi on `rook-ceph-block`) and a
  no-persistence Redis (`manyfold-redis`). `DATABASE_*` env comes from the
  operator's `manyfold-db-app` Secret, `REDIS_URL` points at
  `manyfold-redis`, and `SECRET_KEY_BASE` comes from `manyfold-secret`
  (`manyfold-secret.sops.yaml`, WDO-163).
- `PUID`/`PGID` `3000` (the bignas `orion` user): the prints NFS export has
  no squash, so the effective UID/GID must be explicit to keep NAS file
  ownership stable (see `clusters/orion/docs/nas.md`). The image's s6
  entrypoint starts as root, prepares the database and steps down to
  `PUID`/`PGID` via `s6-setuidgid`; the pod therefore keeps the upstream
  recommended capability set (`CHOWN`, `DAC_OVERRIDE`, `SETUID`,
  `SETGID` on top of a dropped `ALL`) while the root filesystem stays
  read-only (the image ships `S6_READ_ONLY_ROOT=1`).
- `MULTIUSER=enabled`, `HTTPS_ONLY=enabled` and `PUBLIC_HOSTNAME` (the
  `${subdomain}.${domain}` route) — `PUBLIC_HOSTNAME` is what makes Rails
  trust the gateway's `X-Forwarded-Proto` (`config.assume_ssl`), so
  `HTTPS_ONLY` does not redirect-loop behind the SSL-terminating gateway.
- `WEB_CONCURRENCY=2` / `RAILS_MAX_THREADS=8`: worst case
  `2*8 + 4 + 1 = 21` database connections (web threads + Sidekiq
  concurrency defaults), inside the CNPG default `max_connections`.

## Storage

| Mount | PVC | Backing | Use |
|---|---|---|---|
| `/libraries` | `manyfold-libraries` | static PV `nas-prints` (bignas `storage/prints`, 1Ti) | the library root |
| `/usr/src/app/plugins` | `manyfold-data` | `rook-ceph-block`, 1Gi | optional plugins (upstream's documented persistent path) |

`/run`, `/usr/src/app/tmp` and `/usr/src/app/log` are `emptyDir` scratch —
the root filesystem stays read-only.

## Adding models

1. **Browser upload:** drag files onto a library in the web UI (up to
   `MAX_FILE_UPLOAD_SIZE`, 1GiB per file by default). Uploads are extracted
   into the library and scanned.
2. **Bulk copies:** put files on the bignas `prints` share (SMB from a
   desktop, or NFS). They appear in the container at `/libraries`. In the
   web UI, create or edit a library and point it at the folder, then scan;
   re-scan after adding more files.
3. **The library path is added once in Manyfold's settings on first run** —
   create the first library against `/libraries` (or a subfolder) after
   opening the site; further libraries can point at subfolders of the same
   mount.

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(subdomain `models`). Homepage lists it under the **Home** group
(`manyfold.png`). Health probes hit `/health` — Manyfold's documented
health endpoint, which the app also excludes from its HTTPS redirect.

## First run

1. Wait for Flux to reconcile: the `manyfold-db` CNPG Cluster boots before
   the app (see the `dependsOn` in `clusters/orion/manyfold.yaml`), and the
   pod's startupProbe allows minutes for the first-boot migrations.
2. Open the site, create the administrator account (multiuser mode is on),
   and add the first library against `/libraries` (see above).
3. Check the PVC is `Bound`: `kubectl get pvc -n manyfold` should show
   `manyfold-libraries` bound to `nas-prints` (Jon or Calvin, read-only).
