# Orion Cluster — Talos OS Layer

Bare-metal provisioning source-of-truth for the **orion** Talos Kubernetes cluster.
The Flux GitOps layer lives in `../../kubernetes/clusters/orion/`.

## Version matrix

| Component | Version |
|---|---|
| Talos | v1.12.1 |
| Kubernetes | v1.33.0 |
| Cilium | managed by Flux (see `kubernetes/infrastructure/cilium/`) |

## Cluster summary

| Property | Value |
|---|---|
| Control-plane nodes | 3× Beelink GK Mini |
| Worker nodes | 2× Bosgame |
| VIP | 10.50.0.10 (VLAN 50) |
| API endpoint | `https://10.50.0.10:6443` / `orion-api.norseamerican.com` |
| Pod CIDR | 10.241.0.0/16 |
| Service CIDR | 10.141.0.0/16 |

See `NODES.md` for the per-node hardware identity table (MACs, disk paths, IPs).

## Directory layout

```
clusters/orion/
├── talconfig.yaml          # talhelper input — declarative cluster + node config
├── talsecret.sops.yaml     # SOPS-encrypted PKI bundle (committed; decrypted by talhelper at gen time)
├── NODES.md                # per-node hardware inventory
├── patches/
│   ├── cluster/            # applied to every node
│   ├── controlplane/       # applied to control-plane nodes only
│   ├── worker/             # applied to worker nodes only (reserved)
│   └── nodes/              # per-node patches (certSANs)
├── clusterconfig/          # talhelper output — gitignored; regenerate with task talos:gen-config
└── docs/
    ├── network-topology.md
    ├── bootstrap.md        # new-cluster bring-up
    ├── upgrade.md          # Talos + K8s upgrades
    ├── recovery.md         # etcd backup, node loss, secret policy
    └── add-replace-node.md
```

## Common commands

```bash
# Render machineconfigs
task talos:gen-config

# Validate configs (talhelper + talosctl)
task talos:validate

# Apply to a single node
task talos:apply NODE=orion-cp-01 IP=10.50.0.11

# Apply all nodes (first-time bootstrap — insecure mode)
task talos:apply-all INSECURE=true

# Check cluster health
task talos:health

# Upgrade Talos on one node
task talos:upgrade-talos NODE=orion-cp-01 IP=10.50.0.11 IMAGE=ghcr.io/siderolabs/installer:v1.12.1

# Upgrade Kubernetes
task talos:upgrade-k8s TO=v1.33.0
```

## Secrets

`talsecret.sops.yaml` is encrypted with age (key at `~/.config/sops/age/keys.txt`).
`talhelper genconfig` decrypts it automatically at render time — no manual step needed.

**Never regenerate secrets on a live cluster.** See `docs/recovery.md` for the rotation policy.
