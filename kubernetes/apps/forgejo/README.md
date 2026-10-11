# forgejo

Self-hosted git forge at `git.${domain}` (HTTPS git only). Postgres via a CNPG
`Cluster` (`forgejo-db`); repos, packages and the OCI registry live on the
`rook-ceph-block` PVC. Admin credentials are in `secret.yaml` (sops).
