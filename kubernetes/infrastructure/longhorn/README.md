# longhorn

Distributed block storage providing `ReadWriteOnce` and `ReadWriteMany` PersistentVolumes backed by node-local disks.

## Configuration

- **Chart:** `longhorn/longhorn` v1.7.2 (pinned)
- **Namespace:** `longhorn-system`
- **Values source:** HelmRelease inline (minimal overrides)

An ingress is defined in `ingress.yaml` for the Longhorn UI. Access credentials are in `secret.yaml` (SOPS-encrypted, used for basic-auth on the ingress).

## Dependencies

Cilium or nginx must be ready for the UI ingress to work. Core storage functionality does not depend on ingress.

## Ingress / Endpoints

Longhorn UI is exposed via ingress (see `ingress.yaml` for the hostname).

## Troubleshooting

- **PVC stuck in `Pending`:** Check that Longhorn has at least one schedulable replica (`kubectl -n longhorn-system get nodes.longhorn.io`).
- **Volume degraded:** A node may be offline. Check `kubectl -n longhorn-system get volumes.longhorn.io`.
- **UI inaccessible:** Verify ingress and that the basic-auth secret is properly decrypted.
