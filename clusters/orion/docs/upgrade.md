# Upgrade Runbook

## Upgrading Talos

Upgrade one node at a time. Drain workloads from the node before upgrading control-plane nodes.

```bash
# Drain the node (from a kubectl context)
kubectl drain orion-cp-01 --ignore-daemonsets --delete-emptydir-data

# Upgrade Talos on that node
task talos:upgrade-talos NODE=orion-cp-01 IP=10.50.0.11 IMAGE=ghcr.io/siderolabs/installer:v1.12.1

# Wait for the node to rejoin (watch talosctl health or kubectl get nodes)
# Uncordon once healthy
kubectl uncordon orion-cp-01
```

Repeat for each node. Workers first is safer for etcd quorum but not required for a 3-CP cluster.

After upgrading all nodes, update `talosVersion` in `talconfig.yaml` and re-render:

```bash
task talos:gen-config
task talos:validate
```

## Upgrading Kubernetes

```bash
task talos:upgrade-k8s TO=v1.33.0
```

This runs `talosctl upgrade-k8s` which upgrades the control-plane components and kubelet on all nodes. Talos handles the rolling upgrade automatically.

After upgrading, update `kubernetesVersion` in `talconfig.yaml` and re-render:

```bash
task talos:gen-config
task talos:validate
```

## Checking current versions

```bash
talosctl -n 10.50.0.10 version
kubectl version
```
