# csi-driver-nfs

The [CSI NFS driver](https://github.com/kubernetes-csi/csi-driver-nfs) (chart
pinned at `4.13.6`), installed through Flux so NFS dynamic provisioning is
available. The bignas stores are **static** PVs — see
[nas-storage](../nas-storage/README.md) — so nothing is provisioned behind
your back. Dynamic provisioning is used deliberately and per-app: the first
(and only) `StorageClass` is `nfs-backups-pg`, created inside
`kubernetes/apps/rustfs/` for the CNPG backup endpoint (GH #324).

No `StorageClass` ships with the chart (`storageClass.create: false`): a
default-class accident would hijack PVCs meant for Ceph. Any new StorageClass
lives in the app that needs it, is never the cluster default, and names its
NAS share explicitly. All chart images are pinned by the chart itself
(`registry.k8s.io/sig-storage/*`).

The node plugin runs a privileged DaemonSet on every node (standard for CSI);
no Talos extension or node change is required — kubelet mounts NFSv4 with the
in-kernel client.

`release.yaml` carries one-shot `reconcile.fluxcd.io/requestedAt` and
`reconcile.fluxcd.io/forceAt` annotations: the controller acts on each token
value once, then ignores it. To re-force a release, change both values to a
new arbitrary token.
