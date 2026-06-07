# Orion Cluster — Node Hardware Inventory

> **Sensitivity:** This file contains hardware MAC addresses and disk serials that
> uniquely identify physical machines. Keep this repository private or remove this
> file before making the repo public.

## Control Plane Nodes — Beelink GK Mini

Trunk NIC: `enp2s0` (bus `0000:02:00.0`, Realtek r8169). Boot disk: SATA 128 GB SSD.

| Hostname | K8s IP (VLAN 50) | Mgmt IP (VLAN 10) | NIC MAC (`enp2s0`) | Boot disk (by-id) |
|---|---|---|---|---|
| orion-cp-01 | 10.50.0.11/24 | 10.10.0.11/24 | `84:47:09:07:c6:4a` | `ata-SSD_128GB_2021092600394` |
| orion-cp-02 | 10.50.0.12/24 | 10.10.0.12/24 | `84:47:09:07:c4:ff` | `ata-SSD_128GB_2021092601145` |
| orion-cp-03 | 10.50.0.13/24 | 10.10.0.13/24 | `5c:85:7e:4f:a2:92` | `ata-ORICO_250929CA12802668` |

Additional disks on CP nodes (Ceph OSD candidates):
- orion-cp-02: Samsung SSD 870 QVO 2 TB (`ata-Samsung_SSD_870_QVO_2TB_S6R4NJ0W405219J`)
- orion-cp-03: NGFF 2280 128 GB SSD (`ata-NGFF_2280_128GB_SSD_2021031902002`)

## Worker Nodes — Bosgame

Trunk NIC: `enp1s0` (bus `0000:01:00.0`). Boot disk: Kingston 1 TB NVMe. A second `enp2s0` NIC is present but carries no addresses in the new config (the old doubled-interface bug configured VLANs on both).

| Hostname | K8s IP (VLAN 50) | Mgmt IP (VLAN 10) | NIC MAC (`enp1s0`) | Boot disk (by-id) |
|---|---|---|---|---|
| orion-w-01 | 10.50.0.21/24 | 10.10.0.21/24 | `84:47:09:53:24:d6` | `nvme-KINGSTON_OM8PGP41024N-A0_50026B7383880325` |
| orion-w-02 | 10.50.0.22/24 | 10.10.0.22/24 | `84:47:09:53:28:36` | `nvme-KINGSTON_OM8PGP41024N-A0_50026B738388057D` |

Additional disks on worker nodes (Ceph OSD candidates):
- orion-w-01: WD_BLACK SN7100 2 TB (`nvme-WD_BLACK_SN7100_2TB_...` — capture with `talosctl get disks`)
- orion-w-02: NX-2TB 2280 (`nvme-...` — capture with `talosctl get disks`)

## Cluster VIP

`10.50.0.10` — Talos VIP on VLAN 50, declared on all three control-plane nodes via `vip.ip`.

## Network

| VLAN | Purpose | Subnet | Gateway |
|---|---|---|---|
| 50 | Kubernetes | 10.50.0.0/24 | 10.50.0.1 |
| 10 | Management | 10.10.0.0/24 | 10.10.0.1 |
| 60 | LoadBalancer services | 10.60.0.0/24 | 10.60.0.1 |

See `docs/network-topology.md` for the full switch/VLAN diagram.

## Capturing hardware identity

To refresh this table after hardware changes:

```bash
# NIC permanent MAC
talosctl get links enp2s0 --talosconfig clusters/orion/clusterconfig/talosconfig --nodes <ip> -o yaml | grep "permanentAddr:"

# Disk by-id symlinks
talosctl get disks --talosconfig clusters/orion/clusterconfig/talosconfig --nodes <ip> -o yaml | grep "by-id/"
```
