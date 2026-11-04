# firefly

[Firefly III](https://firefly-iii.org) — personal finance manager.
Single `fireflyiii/core` container backed by a CNPG PostgreSQL cluster.

## Configuration

- **Namespace:** `firefly`
- Listens on the base's default `8080`, so no port patch is needed.
- Database: CNPG `Cluster` `firefly-db` (1 instance, 5Gi on
  `rook-ceph-block`, in `database.yaml`). The operator creates Secret
  `firefly-db-app`; `deploy-add-env.yaml` maps its `host`, `port`, `dbname`,
  `user` and `password` keys to Firefly's `DB_*` variables.
- Uploads: PVC `firefly-upload` (1Gi on `rook-ceph-block`) mounted at
  `/var/www/html/storage/upload`.
- Secrets: `APP_KEY` and `STATIC_CRON_TOKEN` live in
  `firefly-secrets.sops.yaml` (Secret `firefly-secrets`). The file is
  included by the root `kustomization.yaml`, outside the app's `namePrefix`:
  the Secret was encrypted under that name, and renaming an encrypted file
  breaks its SOPS MAC.
- The image runs as `www-data` (uid/gid 33); `deploy-security-context.yaml`
  pins that and sets `fsGroup: 33` so the upload PVC is writable.

## Cron

`cronjob.yaml` runs daily at 03:00 America/Boise and calls
`GET /api/v1/cron/<STATIC_CRON_TOKEN>` on `firefly-svc:8080` (recurring
transactions, auto-budgets, exchange rates, bill notifications). The token
is mounted as a file and piped to curl over stdin, so it never appears in
argv or in curl's error output.

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(subdomain `firefly`). gethomepage.dev annotations surface it under
"Finances".

## First run

WARNING: Register an admin user immediately after the first deploy. Firefly
III's registration page stays open until the first account exists.

## Troubleshooting

- **CrashLoopBackOff on boot:** If the `firefly-db-app` Secret does not
  exist yet, the Deployment cannot resolve its `DB_*` variables. Wait for
  the CNPG cluster to go ready (`kubectl get cluster -n firefly`).
- **Uploads fail with permission denied:** Confirm `fsGroup: 33` survived
  on the rendered pod spec (`kubectl get deploy -n firefly -o yaml`).
- **Cron did not run:** Check `kubectl -n firefly logs job/firefly-cron-<id>`.
  curl retries up to 3 times per run (`retry = 3` in its config file) and the
  Job itself has `backoffLimit: 0`, so a failed Job waits for the next
  schedule. `concurrencyPolicy: Forbid` skips runs while a previous one is
  active.
