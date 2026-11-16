# bookorbit

[BookOrbit](https://github.com/bookorbit/bookorbit) — self-hosted PDF and
ebook library with a web reader, audiobook support, and OPDS/Kobo sync.
Built on `webapp/base` with the `httproute` and `pvc` components.

## Configuration

- **Namespace:** `bookorbit`.
- Image `ghcr.io/bookorbit/bookorbit:3.8.0`, pinned by digest. Container
  listens on `3000`; the `replacements` block in `app/kustomization.yaml`
  keeps the Service port and HTTPRoute backendRef in sync.
- Postgres via a CNPG `Cluster` (`bookorbit-db`, 1 instance, 5Gi on
  `rook-ceph-block`). The **standard** CNPG image is required: it ships the
  `pgvector` extension (plus `uuid-ossp`, `pg_trgm`, `unaccent`) that
  BookOrbit's migrations create on first boot. `POSTGRES_*` env comes from
  the operator's `bookorbit-db-app` Secret.
- `JWT_SECRET`/`SETUP_BOOTSTRAP_TOKEN` come from `bookorbit-secret`
  (`bookorbit-secret.sops.yaml`, WDO-158). Values live with Jon; the
  `SETUP_BOOTSTRAP_TOKEN` header is required for the initial
  `/auth/setup` call.
- The container runs as UID/GID 3000 (the bignas `orion` user): the books
  NFS export has no squash, so the pod's UID must be explicit to keep NAS
  file ownership stable (see `clusters/orion/docs/nas.md`). `fsGroup: 3000`
  makes the CSI drivers chown `/data` and `/tmp` to gid 3000.

## Storage

| Mount | PVC | Backing | Use |
|---|---|---|---|
| `/books` | `bookorbit-books` | static PV `nas-books` (bignas `storage/books`, 1Ti) | the library root |
| `/data` | `bookorbit-data` | `rook-ceph-block`, 2Gi | app data: covers, Book Dock, DB-side caches |

The root filesystem stays read-only (upstream runs `read_only: true`);
`/tmp` is a memory-backed `emptyDir`.

## Loading books

1. **Browser upload:** drag files onto a library in the web UI. Uploads land
   in the Book Dock folder (`/data/book-dock`) and are ingested into the
   selected library.
2. **Bulk copies:** put files on the bignas `books` share (SMB from a
   desktop, or NFS), one subfolder per library under `/books`. In the web UI,
   create or edit a library and pick the folder (`LIBRARY_BROWSE_ROOT` limits
   the picker to `/books`), then scan. Re-scan after adding more files.

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(subdomain `books`). Homepage lists it under the **Home** group
(`bookorbit.png`). Health probes hit `/api/v1/health` — the same endpoint as
upstream's image `HEALTHCHECK`.

## First run

1. Read `SETUP_BOOTSTRAP_TOKEN` from the secret (`sops -d
   bookorbit-secret.sops.yaml`) — it authorizes the initial setup API call
   (`x-setup-token` header).
2. Open the site, complete setup, and create an administrator.
3. Create a library against a folder under `/books` and scan (see above).

## Not yet wired

- No TTS (`kokoro`) or read-aloud worker — upstream compose profiles, left
  out of this deployment on purpose (WDO-157).
