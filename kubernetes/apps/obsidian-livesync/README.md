# obsidian-livesync

CouchDB backend for the [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync)
Obsidian plugin. Obsidian itself stays local on each device — this just
gives the plugin something to sync against. Built on `webapp/base` with
`httproute` + `pvc`.

## Configuration

- **Namespace:** `obsidian-livesync`
- Official `couchdb` image, non-root (uid/gid `5984`); `deploy-security-context.yaml`
  sets `fsGroup: 5984` so the PVC is writable.
- PVC via the `pvc` component, remounted to `/opt/couchdb/data` (CouchDB's
  compiled-in data dir) — 5Gi on `rook-ceph-block` by default (see
  `postBuild.substitute` in `clusters/orion/obsidian-livesync.yaml`).
- `files/local.ini` → `configMapGenerator` → mounted at
  `/opt/couchdb/etc/local.d/local.ini`. Sets CORS for the plugin's two
  origins (`app://obsidian.md` desktop, `capacitor://localhost` mobile) and
  bumps `max_document_size`/`max_http_request_size` for large vaults.
- Admin credentials via `COUCHDB_USER`/`COUCHDB_PASSWORD` env, sourced from
  `secret.yaml` (sops-encrypted) — the official image (re)creates the admin
  user from these on every boot.

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(`obsidian.orion.norseamerican.com`). No auth in front beyond CouchDB's own
basic auth — treat the admin password as the only gate on the vault.

## First run

1. `secret.yaml` ships sops-encrypted with a generated admin user/password
   (`couchdbUser: obsidian`). Read it back with `sops -d secret.yaml` if you
   need the password; rotate with `sops secret.yaml` (opens decrypted in
   `$EDITOR`, re-encrypts on save).
2. In Obsidian, install "Self-hosted LiveSync" and point it at
   `https://obsidian.orion.norseamerican.com` with those credentials. Use
   the plugin's "Test Database Connection" / setup wizard — it creates the
   sync database and design docs itself, no manual `PUT` needed.
3. Repeat on each additional device, pointing at the same URL/database so
   they converge on one vault.

## Migrating an existing vault

LiveSync's first sync is a blunt push or pull, not a merge — do any
consolidation on disk first.

1. Back up each existing vault folder.
2. If merging notes from more than one vault, manually copy the unique
   files from the non-primary vault(s) into whichever vault will be
   primary, resolving any same-path conflicts by hand.
3. On the primary device: install the plugin, choose **"I am setting this
   up for the first time"** → the **new-device path** (rebuilds the remote
   from local). Do this on LAN if the vault has a lot of attachments — the
   initial chunk upload of a large vault over WAN can be slow/flaky. A
   "Fetch Remote Configuration Failed" notice on this first run is
   expected (empty DB) — skip it. Wait for the sync indicator to clear
   before touching another device.
4. On every other device: connect as the **existing-device path**
   (fetches and *replaces* local content — only safe once step 2 is done).
   Fastest way: run **"Copy settings as a new Setup URI"** on the primary,
   then **"Use a Setup URI"** on the other device.
5. Never run the new-device/rebuild path on more than one device — last
   one to push wins and clobbers the other.

## Troubleshooting

- **Mobile app can't connect / vague network error:** almost always the
  `capacitor://localhost` CORS origin missing from `local.ini` — confirm the
  configMap actually mounted (`kubectl exec -n obsidian-livesync deploy/obsidian-livesync-deploy -- cat /opt/couchdb/etc/local.d/local.ini`).
- **413 / request too large on big attachments:** the Gateway API
  implementation may impose its own body-size cap independent of
  `max_http_request_size` here — check `infrastructure/gateway/` if large
  binary attachments in the vault fail to sync.
- **Data loss after restart:** verify the PVC is bound and mounted at
  `/opt/couchdb/data`, not the pvc component's `/data` default
  (`kubectl describe pod -n obsidian-livesync`).
