# Bootstrap — New Cluster Bring-Up

This runbook covers standing up the orion cluster from scratch. It assumes all five nodes are booted from a Talos ISO and are in maintenance mode.

## Prerequisites

- `talhelper`, `talosctl`, `sops`, `age`, `task` installed (`task gen:tools` or see `Brewfile`)
- Age private key at `~/.config/sops/age/keys.txt`
- Network switch configured with VLAN 10 and VLAN 50 trunked to each node port
- Talos ISO (generated via [factory.talos.dev](https://factory.talos.dev)) booted on each node

## 1. Generate the cluster secret bundle

**Only run this once per cluster lifetime.** The secrets establish the cluster's PKI identity; regenerating them requires a full re-bootstrap.

If starting fresh:

```bash
cd clusters/orion
talhelper gensecret > talsecret.sops.yaml
sops --encrypt --in-place talsecret.sops.yaml
```

If migrating from an existing live cluster (preserves node trust):

```bash
task talos:gen-secret FROM=clusters/orion/rendered/orion-cp-01-complete.yaml
```

Commit `talsecret.sops.yaml`. Never commit the decrypted form.

## 2. Capture hardware identities

Before rendering configs, fill in the `NODES.md` table with real MAC addresses and disk by-id paths. With nodes in maintenance mode (before they have a Talos client cert):

```bash
# Discover disks (use --insecure since there's no client cert yet)
talosctl -n 10.50.0.11 --insecure get disks -o yaml

# Discover NIC MACs
talosctl -n 10.50.0.11 --insecure get links -o yaml | grep -A3 'name: eth0'
```

Update `talconfig.yaml` to replace `interface: eth0` / `interface: enp1s0` with `deviceSelector.hardwareAddr: <MAC>` for each node. See `NODES.md` for the table.

## 3. Render machineconfigs

```bash
task talos:gen-config
```

Output lands in `clusterconfig/` (gitignored). Validate before applying:

```bash
task talos:validate
```

## 4. Apply configs (first time — insecure)

In maintenance mode the nodes have no client certificate yet, so pass `INSECURE=true`:

```bash
task talos:apply-all INSECURE=true
```

Or apply one at a time:

```bash
task talos:apply NODE=orion-cp-01 IP=10.50.0.11 INSECURE=true
task talos:apply NODE=orion-cp-02 IP=10.50.0.12 INSECURE=true
task talos:apply NODE=orion-cp-03 IP=10.50.0.13 INSECURE=true
task talos:apply NODE=orion-w-01  IP=10.50.0.21 INSECURE=true
task talos:apply NODE=orion-w-02  IP=10.50.0.22 INSECURE=true
```

Nodes reboot after receiving config. Wait for control-plane nodes to come up (check `talosctl -n <ip> health`).

## 5. Bootstrap etcd

Run **once** against the first control-plane node only:

```bash
task talos:bootstrap
```

## 6. Fetch kubeconfig

```bash
task talos:kubeconfig
```

Writes `./kubeconfig`. Verify cluster access: `kubectl get nodes`.

## 7. Install Cilium

Cilium is the CNI; the cluster won't be fully functional until it's installed. Follow the instructions in `kubernetes/infrastructure/cilium/README.md`.

The Cilium taint (`node.cilium.io/agent-not-ready`) on all nodes is applied via `patches/cluster/30-cilium-prep.yaml`. Pods will not schedule until Cilium removes it.

## 8. Bootstrap Flux

```bash
task flux:install
```

This installs Flux into `kube-system` and points it at `kubernetes/clusters/orion/` in this repo. From this point forward, infrastructure and apps are managed by Flux.

## Troubleshooting

**Node won't get an IP:** Verify VLAN trunk on switch port. Check that `deviceSelector.hardwareAddr` (or interface name) matches the actual NIC. Run `talosctl -n <ip> --insecure get links -o yaml`.

**etcd bootstrap times out:** Ensure all three CPs have their configs applied and have rebooted before running `task talos:bootstrap`.

**Kubeconfig `connection refused`:** The VIP (`10.50.0.10`) is only active after etcd is bootstrapped and at least one CP is healthy. Check `task talos:health`.
