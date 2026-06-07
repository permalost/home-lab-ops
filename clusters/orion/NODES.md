# Orion Cluster — Node Hardware Inventory

This file is the canonical record of per-node hardware identity. Update it whenever a node is replaced or re-imaged.

## Control Plane Nodes — Beelink GK Mini

| Hostname | Role | K8s IP (VLAN 50) | Mgmt IP (VLAN 10) | Boot Disk (by-path) | NIC MAC | Chassis S/N |
|---|---|---|---|---|---|---|
| orion-cp-01 | controlplane | 10.50.0.11/24 | 10.10.0.11/24 | `/dev/disk/by-path/pci-0000:00:12.0-ata-1` | **TODO** | **TODO** |
| orion-cp-02 | controlplane | 10.50.0.12/24 | 10.10.0.12/24 | `/dev/disk/by-path/pci-0000:00:12.0-ata-1` | **TODO** | **TODO** |
| orion-cp-03 | controlplane | 10.50.0.13/24 | 10.10.0.13/24 | `/dev/disk/by-path/pci-0000:00:12.0-ata-1` | **TODO** | **TODO** |

## Worker Nodes — Bosgame

| Hostname | Role | K8s IP (VLAN 50) | Mgmt IP (VLAN 10) | Boot Disk (by-path) | NVMe (Ceph) | NIC MAC | Chassis S/N |
|---|---|---|---|---|---|---|---|
| orion-w-01 | worker | 10.50.0.21/24 | 10.10.0.21/24 | `/dev/disk/by-path/pci-0000:04:00.0-nvme-1` | TBD | **TODO** | **TODO** |
| orion-w-02 | worker | 10.50.0.22/24 | 10.10.0.22/24 | `/dev/disk/by-path/pci-0000:04:00.0-nvme-1` | TBD | **TODO** | **TODO** |

## Filling in MAC addresses

Once captured, replace the `interface: eth0` / `interface: enp1s0` entries in `talconfig.yaml` with MAC-based device selectors so the config survives firmware upgrades or kernel renames:

```yaml
# Replace this …
- interface: eth0

# … with this (one entry per node using its real MAC):
- deviceSelector:
    hardwareAddr: "aa:bb:cc:dd:ee:ff"
```

To retrieve the MAC for a running node:

```bash
talosctl -n <ip> get links -o yaml | grep -A2 'name: eth0\|name: enp'
```

To retrieve disk identities (for upgrading from by-path to by-id, which is more stable):

```bash
talosctl -n <ip> get disks -o yaml
```

## Cluster VIP

`10.50.0.10` — Talos VIP declared on VLAN 50 on each control-plane node. Whoever holds the VIP is the active API server endpoint.

## Network summary

| VLAN | Purpose | Subnet | Gateway |
|---|---|---|---|
| 50 | Kubernetes (pod/service traffic) | 10.50.0.0/24 | 10.50.0.1 |
| 10 | Management | 10.10.0.0/24 | 10.10.0.1 |
| 60 | LoadBalancer services | 10.60.0.0/24 | 10.60.0.1 |

See `docs/network-topology.md` for the full switch/VLAN diagram.
