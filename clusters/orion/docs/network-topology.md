# Orion Cluster - Network Topology

## Overview

The Orion cluster uses VLAN-based network segmentation for security and traffic isolation.

## VLAN Design

### VLAN 50 - Kubernetes Network (Primary)
- **Subnet:** 10.50.0.0/24
- **Gateway:** 10.50.0.1
- **Purpose:** Kubernetes control plane and pod network
- **Nodes:**
  - 10.50.0.10 - Control Plane VIP (KubePrism)
  - 10.50.0.11 - orion-cp-01
  - 10.50.0.12 - orion-cp-02
  - 10.50.0.13 - orion-cp-03
  - 10.50.0.21-30 - Workers (future)

### VLAN 10 - Management Network
- **Subnet:** 10.10.0.0/24
- **Gateway:** 10.10.0.1
- **Purpose:** Out-of-band management, monitoring, SSH access
- **Nodes:**
  - 10.10.0.11 - orion-cp-01 (mgmt)
  - 10.10.0.12 - orion-cp-02 (mgmt)
  - 10.10.0.13 - orion-cp-03 (mgmt)

### VLAN 60 - Service Network
- **Subnet:** 10.60.0.0/24
- **Gateway:** 10.60.0.1
- **Purpose:** LoadBalancer IPs for services
- **Services:**
  - 10.60.0.10 - Ingress (production)
  - 10.60.0.53 - Pihole DNS
  - 10.60.0.60 - Home Assistant
  - 10.60.0.70 - Grafana

## Physical Topology
```
┌─────────────────────────────────────────────────────┐
│ UDM Pro (10.10.0.1)                                 │
│ - Core Router/Firewall                              │
│ - DHCP Server (all VLANs)                          │
│ - DNS Forwarder → Pihole                           │
└──────────────────┬──────────────────────────────────┘
                   │ 10G SFP+ Trunk (all VLANs)
                   │
┌──────────────────┴──────────────────────────────────┐
│ 10G Switch (10.10.0.3)                              │
│ - High-speed cluster backbone                       │
│ - 8x 2.5G ports, 2x 10G SFP+                       │
└──┬───────┬───────┬───────┬──────────────────────────┘
   │       │       │       │
   │ 2.5G  │ 2.5G  │ 2.5G  │ ... (workers)
   │       │       │       │
   │       │       │       │
┌──┴───┐ ┌─┴────┐ ┌┴─────┐
│ CP-01│ │ CP-02│ │ CP-03│
│ .11  │ │ .12  │ │ .13  │
└──────┘ └──────┘ └──────┘

VLAN Tagging on each port:
- Tagged: VLAN 10 (Management)
- Tagged: VLAN 50 (Kubernetes)
```

## Traffic Flow

### Control Plane Communication
```
etcd cluster:
  orion-cp-01 ←→ orion-cp-02 ←→ orion-cp-03
  (10.50.0.11)   (10.50.0.12)   (10.50.0.13)
  Port 2379-2380 on VLAN 50

API Server:
  Clients → 10.50.0.10:6443 (VIP)
    ↓
  KubePrism routes to healthy control plane nodes
    ↓
  orion-cp-01:6443, orion-cp-02:6443, orion-cp-03:6443
```

### Storage (Ceph) Communication
```
Ceph OSDs:
  Each control plane node runs OSD on /dev/nvme0n1

Ceph traffic:
  OSD ←→ OSD communication on VLAN 50
  Client ←→ OSD (RBD mounts) on VLAN 50

Ceph monitors:
  Co-located with etcd on control plane nodes
```

### Service Access
```
External Client (VLAN 20)
  ↓
UDM Pro Firewall (allow VLAN 20 → VLAN 60)
  ↓
LoadBalancer IP (VLAN 60) - e.g., 10.60.0.70 (Grafana)
  ↓
Cilium L2 announcement from node
  ↓
Ingress Controller Pod (VLAN 50)
  ↓
Service → Backend Pods
```

## DNS Resolution

### Internal DNS
```
Client query for orion-api.yourdomain.local
  ↓
UDM Pro DNS forwards to Pihole ($PIHOLE_IP)
  ↓
Pihole resolves:
  orion-api.yourdomain.local → $CLUSTER_VIP
  orion-cp-01.yourdomain.local → $CP_01_IP
  *.orion.yourdomain.local → $INGRESS_IP (wildcard for ingress)
```
