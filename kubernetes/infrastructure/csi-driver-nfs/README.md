# csi-driver-nfs

The [CSI NFS driver](https://github.com/kubernetes-csi/csi-driver-nfs) (chart
pinned at `4.13.6`), installed through Flux so NFS dynamic provisioning is
available. The bignas mounts themselves are **static** — see
[nas-storage](../nas-storage/README.md) — so nothing is provisioned behind
your back; the driver exists for future dynamically-provisioned NFS volumes.

No `StorageClass` is created (`storageClass.create: false`): with static PVs
one is not needed, and a default-class accident would hijack PVCs meant for
Ceph. All chart images are pinned by the chart itself
(`registry.k8s.io/sig-storage/*`).

The node plugin runs a privileged DaemonSet on every node (standard for CSI);
no Talos extension or node change is required — kubelet mounts NFSv4 with the
in-kernel client.
