# forgejo

Self-hosted git forge at `git.${domain}` (HTTPS git only). Postgres via a CNPG
`Cluster` (`forgejo-db`); repos, packages and the OCI registry live on the
`rook-ceph-block` PVC. Admin credentials are in `secret.yaml` (sops).

Backups: `forgejo-db` is backed up daily (10:00 UTC) via the barman-cloud
plugin to the RustFS object store — ObjectStore, ScheduledBackup and the
plugin wiring live in this directory; PITR/restore procedure in
`kubernetes/infrastructure/cnpg/README.md`.
