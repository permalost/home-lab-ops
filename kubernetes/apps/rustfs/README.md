# rustfs — S3-compatible backup endpoint on the NAS

Single-replica [RustFS](https://rustfs.com) (Apache-2.0, S3 API) whose data
lives on the bignas `backups/orion/tier1-critical` export. It is the object
store CNPG's `plugin-barman-cloud` writes base backups + WAL to (spec #321,
GH #324 → #325); CNPG cannot write to plain NFS — S3 API only.

- **Endpoint (in-cluster):** `http://rustfs.storage-system.svc:9000`
  — no HTTPRoute, nothing is exposed outside the cluster.
- **Data path:** PVC `data` → StorageClass `nfs-backups-pg` → dynamic
  provisioning via `csi-driver-nfs` into `/mnt/storage/backups/orion/
  tier1-critical/pg` on bignas (subdirectory `pg`, created by the driver on
  first provision — no separate NAS export).
- **Credentials:** `Secret/rustfs-credentials` (SOPS, `access-key` /
  `secret-key`), wired to the Deployment as `RUSTFS_ACCESS_KEY` /
  `RUSTFS_SECRET_KEY`. Rotate by editing the plaintext values, re-running
  `sops --encrypt --in-place`, and restarting the pod.
- **Bucket:** `orion-cnpg`, created at container start by the image's own
  bootstrap (`configmap-bootstrap.yaml` overrides the image's
  `/etc/rustfs/bootstrap/buckets.json`; idempotent on every restart). The
  #325 `ObjectStore` CR should set `bucketName: orion-cnpg`.
- **Image:** `rustfs/rustfs:1.0.7` pinned by digest; runs as non-root
  `10001:10001` natively, so the secure-by-default set holds with no opt-out.
- **Sizing:** PVC requests 100Gi — metadata only on NFS (no dataset quota);
  ~40Gi of raw postgres across the six clusters plus retained backups and
  WAL. The real cap is the bignas pool. (ADR-0002 is not on disk — see
  "ADRs" in `clusters/orion/docs/nas.md`.)

## Verify the S3 round-trip (after deploy)

```bash
# put/get through the Service, from a throwaway pod using the image's own rc client
kubectl run -n storage-system rustfs-roundtrip --rm -it --restart=Never \
  --image=rustfs/rustfs:1.0.7 --overrides '
{"spec":{"containers":[{"name":"rc","image":"rustfs/rustfs:1.0.7","command":["sh","-c","""
set -e
export RC_HOST_check=http://$RUSTFS_ACCESS_KEY:$RUSTFS_SECRET_KEY@rustfs.storage-system.svc:9000
echo roundtrip | rc pipe check/orion-cnpg/roundtrip.txt
rc object show check/orion-cnpg/roundtrip.txt
"""],"envFrom":[{"secretRef":{"name":"rustfs-credentials"}}]}}]}}'
```

Expect `roundtrip` echoed back. Remove the probe object afterwards with
`rc object remove check/orion-cnpg/roundtrip.txt` (or leave it; it is a
10-byte object). The same round-trip was verified locally against the
1.0.7 binary + entrypoint before shipping (see PR notes).

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| Pod `Pending`, PVC unbound | `csi-driver-nfs` not ready, or bignas unreachable | `kubectl get pvc -n storage-system`; `task backup:nas-status` |
| `ContainerCreating` forever | NFS mount failing (export networks, NFS service off) | pod events; nas.md troubleshooting table |
| `permission denied` on start | `pg` subdir not writable by 10001 | the StorageClass `mountPermissions`; NAS export networks |
| 403 on S3 calls | credentials mismatch | compare Secret keys with the caller's (#325) |
| Bucket missing | bootstrap ConfigMap changed or endpoint env unset | pod logs: `Ensuring bootstrap bucket: orion-cnpg` |
