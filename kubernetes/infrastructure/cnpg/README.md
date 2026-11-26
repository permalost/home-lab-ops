# cnpg

CloudNativePG operator and its barman-cloud backup plugin. Apps declare a
`postgresql.cnpg.io/v1` `Cluster` in their own namespace; storage comes from
`rook-ceph-block`.

## Operator

`release.yaml` deploys the `cloudnative-pg` chart (pinned version; operator
1.30.x) into `cnpg-system` from the `cnpg` HelmRepository. `values.yaml` keeps
a single operator replica — the managed clusters carry their own HA.

## Barman cloud plugin (GH #325)

`plugin-barman-cloud-release.yaml` deploys the
[plugin-barman-cloud](https://cloudnative-pg.github.io/plugin-barman-cloud/)
chart into the same namespace — the plugin must live with the operator. Chart
and images are pinned to plugin v0.16.0 (`plugin-barman-cloud-values.yaml`
sets both the daemon and the sidecar tag explicitly); the plugin requires
CNPG 1.30+ (enforced via the HelmRelease `dependsOn`) and cert-manager for
its TLS Issuer/Certificates. The chart also creates the
`objectstores.barmancloud.cnpg.io` CRD.

The plugin is discovered by the operator through the `barman-cloud` Service
labels — no `Plugin` CR is needed.

### Object stores and backups

Each app namespace holds (next to its `Cluster`):

- `Secret/rustfs-credentials` — the RustFS access/secret keys (same values as
  `kubernetes/apps/rustfs/rustfs-credentials.sops.yaml`, re-encrypted per
  namespace; a SOPS MAC covers name and namespace, so one encrypted file
  cannot serve two namespaces).
- `ObjectStore/rustfs-store` — `s3://orion-cnpg/` on
  `http://rustfs.storage-system.svc:9000` (path-style), gzip-compressed WAL
  and base backups, `retentionPolicy: 14d`. Barman stores each cluster under
  `<bucket>/<cluster-name>/` (the `serverName` plugin parameter defaults to
  the Cluster name), so all six clusters share the bucket.
- `ScheduledBackup/daily-backup` — daily plugin backup of the Cluster,
  staggered 30 minutes per cluster from 10:00 UTC. ScheduledBackup uses
  robfig/cron v1, which has no timezone support, so schedules are UTC and the
  America/Boise wall-clock time shifts an hour across DST.
- The `Cluster` itself carries `.spec.plugins` with `isWALArchiver: true`,
  which enables continuous WAL archiving plus plugin base backups.

The credentials secret, ObjectStore and Cluster wiring ship in the same Flux
Kustomization, so archiving never starts against a missing secret. A failed
credential lookup would otherwise fail every `archive_command` and pile WAL
up on the instance PVC.

Recovery window: `retentionPolicy: 14d` on the ObjectStore keeps roughly 14-15
daily base backups plus the WAL between them (ADR-0003 tier-1 daily x 14;
the 24h RPO from spec #321 is covered with a wide margin).

### Restore / PITR

PITR restores a Cluster from the object store with `bootstrap.recovery` +
`externalClusters` pointing at the plugin (see the
[plugin docs](https://cloudnative-pg.github.io/plugin-barman-cloud/docs/usage/)):

```yaml
bootstrap:
  recovery:
    source: source
    recoveryTarget:
      targetTime: "2026-11-26 10:00:00+00"
externalClusters:
  - name: source
    plugin:
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: rustfs-store
        serverName: forgejo-db
```

Restore into a scratch namespace and never against the live cluster (spec
#321's restore drill covers the full procedure).

## Validation

```bash
task gen:validate
task test:build
```
