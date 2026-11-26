# snipe-it

[Snipe-IT](https://snipeitapp.com/) — IT asset lifecycle management
(assets, licenses, accessories, consumables). Built on `webapp/base` with
the `httproute` and `pvc` components.

## Configuration

- **Namespace:** `snipe-it`.
- Image `docker.io/snipe/snipe-it:v8.8.3`, pinned by digest. Container
  listens on `80`; the `replacements` block in `app/kustomization.yaml`
  keeps the Service port and HTTPRoute backendRef in sync.
- **Database:** MariaDB — Snipe-IT supports only MySQL/MariaDB, so the
  CloudNativePG setup other apps use does not apply. The `snipe-it-db`
  StatefulSet (1 replica, `mariadb:11.4.13` pinned by digest, 5Gi on
  `rook-ceph-block` at `/var/lib/mysql`) runs alongside the app, exposed by
  the `snipe-it-db` Service on 3306. The app and the database share
  `DB_PASSWORD` from `snipe-it-secret`.
- `APP_KEY`, `DB_PASSWORD` and `MYSQL_ROOT_PASSWORD` come from
  `snipe-it-secret` (`snipe-it-secret.sops.yaml`, WDO-159). The remaining
  env names are checked against upstream `.env.docker` at `v8.8.3`.
- Migrations run in the image entrypoint (`docker/startup.sh` calls
  `php artisan migrate --force`), not as a separate job — no Job needed.

## Storage

| Mount | PVC | Backing | Use |
|---|---|---|---|
| `/var/lib/snipeit` | `snipe-it-data` | `rook-ceph-block`, 5Gi | uploads, backups, OAuth keys |
| `/var/lib/mysql` | `data` (volumeClaimTemplate) | `rook-ceph-block`, 5Gi | MariaDB datadir |

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(subdomain `assets`). Homepage lists it under the **Inventory** group
(`snipe-it.png`). Health probes hit `/health` — Snipe-IT's own route, which
checks the database connection and writable logs.

## First run

The first visit to the site starts the setup wizard, which creates the
administrator account. Do it right after the deploy, before the URL is
shared.

## Not yet wired

- No mail/SMTP and no LDAP/SAML — left out on purpose (WDO-156).
- No backups beyond the PVCs — `snipeit-dumps` in `/var/lib/snipeit` and the
  MariaDB datadir are not exported anywhere.
- `APP_TRUSTED_PROXIES` is unset: the pod CIDR is not in `cluster-settings`,
  and adding it would put an internal range in the repo. If it is ever added
  there, set `APP_TRUSTED_PROXIES: ${podCidr}` in
  `app/patches/deploy-add-env.yaml`. Until then the access log shows the
  gateway's pod IP instead of the client IP.
