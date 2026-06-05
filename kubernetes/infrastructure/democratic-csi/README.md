# democratic-csi

CSI driver providing dynamic PersistentVolume provisioning from a ZFS NFS share. Enables `ReadWriteMany` volumes backed by NFS exports from a TrueNAS/ZFS host.

## Configuration

- **Chart:** `democratic-csi/democratic-csi` (0.13.x, pinned minor)
- **Namespace:** `democratic-csi`
- **Values source:** ConfigMap (`values.yaml` via kustomize `configMapGenerator`)

NFS connection details and ZFS dataset configuration live in the ConfigMap. TrueNAS API credentials are in `secret.yaml` / `configMap.yaml` (SOPS-encrypted).

## Dependencies

Requires a running ZFS/TrueNAS NFS host accessible from the cluster nodes. NFS client utilities must be present on nodes (Talos includes them; k3s nodes may need manual installation).

## Ingress / Endpoints

None. Provisions storage only.

## Troubleshooting

- **PVC stuck in `Pending`:** Check `kubectl -n democratic-csi logs -l app=democratic-csi` for connection or permission errors to the NFS host.
- **Mount fails on pod:** Verify NFS export permissions allow the node IPs and that `no_root_squash` is set if needed.
- **Talos nodes:** NFS mount support is built-in; no extra extensions required for basic NFS.
