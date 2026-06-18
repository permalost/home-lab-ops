# Plan: BGP (UniFi ↔ orion) + ExternalDNS → Pi-hole, Pi-hole as LAN-wide DNS

Status: **planned / not yet implemented**

## Context

Orion's LoadBalancer VIPs (`10.50.0.230–239`, e.g. gateway `10.50.0.231`,
pihole DNS `10.50.0.232`) are announced only via **Cilium L2/ARP** on VLAN 50, so
they are unreachable from other VLANs — a laptop on VLAN 20 gets `!H`
(host-unreachable) from the UDM when reaching the pihole VIP, so pihole can't
serve the whole LAN. Separately, nothing auto-publishes per-app hostnames
(e.g. `dns.orion.norseamerican.com`) into DNS; pihole has only one hand-written
record.

### Goal (three integrated pieces)
1. **BGP peering** between the UDM Pro and the cluster so LB VIPs are *routed* to
   all VLANs (fixes cross-VLAN reachability).
2. **ExternalDNS** auto-creating records in **Pi-hole** for Gateway/HTTPRoute
   hostnames.
3. **Pi-hole as the resolver for all local networks** (UDM hands it out via DHCP).

### Decisions
- UDM Pro/SE → BGP via FRR config upload.
- Keep LB pool at `10.50.0.230–239` inside the node subnet → **hybrid**: BGP
  advertises `/32` host-routes for off-VLAN clients; L2 announcement stays for
  VLAN-50-local clients.
- **Orion only** (na cluster untouched).
- Cilium **1.19.4** (BGP v2 API). Pi-hole **v6/FTL** (`2025.08.0`) → native
  ExternalDNS `pihole` provider. `listeningMode=all` already set.

### Hard constraint
All **cluster** changes land via **git + Flux only** — never
`kubectl apply`/`patch`/`edit` against orion. The only `kubectl` allowed is
**read-only** (`get`/`logs`/`exec ... cilium bgp ...`) for verification. The
**UDM** pieces (FRR/BGP, per-network DHCP DNS) have no GitOps surface and are
configured in the UniFi UI — those are the only manual steps, and they touch the
router, not the cluster. The FRR snippet is committed here for reference.

---

## Architecture / data flow

```
app HTTPRoute (dns.orion.norseamerican.com, parent = orion Gateway)
        │  ExternalDNS (gateway-httproute source, --provider=pihole)
        ▼
Pi-hole local DNS:  dns.orion.norseamerican.com  →  10.50.0.231 (gateway VIP)
        ▲
client (any VLAN) ── UDM hands out 10.50.0.232 as DNS ──┐
        │                                                │
        └─ query 10.50.0.232 ──► routed via BGP /32 ──► pihole DNS VIP
           web to 10.50.0.231 ──► routed via BGP /32 ──► orion Gateway
```

- `10.50.0.232` = pihole DNS service (resolver clients use).
- `10.50.0.231` = orion Gateway VIP (where app web traffic lands).
- Both are in the LB pool → covered by one BGP advertisement + the existing L2 policy.

---

## Part A — Cilium ⇄ UDM BGP

### Repo changes (`kubernetes/infrastructure/cilium/`)
1. **`values.yaml`** — enable the BGP control plane:
   ```yaml
   bgpControlPlane:
     enabled: true
   ```
2. **New `policies/bgp-policy.yaml`** (v2 API, Cilium ≥1.16):
   - `CiliumBGPClusterConfig` — `nodeSelector: {}` (all nodes); one BGP instance
     `localASN: 65001`; peer `unifi` at `peerAddress: 10.50.0.1/32`,
     `peerASN: 65000`, referencing a `CiliumBGPPeerConfig`.
   - `CiliumBGPPeerConfig` — IPv4 unicast; references a `CiliumBGPAdvertisement`
     via `matchLabels`; default timers.
   - `CiliumBGPAdvertisement` — `advertisementType: Service`,
     `service.addresses: [LoadBalancerIP]`, selecting LB services so the pool's
     `/32`s are advertised. With `externalTrafficPolicy: Local`, Cilium
     advertises each VIP only from the node running its pod (correct
     routing/failover).
3. **`kustomization.yaml`** — add `policies/bgp-policy.yaml` to `resources`.
4. **Keep** `policies/l2-policy.yaml` (hybrid — VLAN-50-local clients still ARP).

### UDM side — MANUAL (UniFi UI)
UniFi → **Settings → Routing → BGP** → upload FRR config (peers = each node's
VLAN-50 IP from `clusters/orion/NODES.md`; directly connected, no multihop):
```
router bgp 65000
  bgp router-id 10.50.0.1
  neighbor 10.50.0.11 remote-as 65001
  neighbor 10.50.0.12 remote-as 65001
  neighbor 10.50.0.13 remote-as 65001
  neighbor 10.50.0.21 remote-as 65001
  neighbor 10.50.0.22 remote-as 65001
  address-family ipv4 unicast
    neighbor 10.50.0.11 activate
    neighbor 10.50.0.12 activate
    neighbor 10.50.0.13 activate
    neighbor 10.50.0.21 activate
    neighbor 10.50.0.22 activate
  exit-address-family
```

---

## Part B — ExternalDNS → Pi-hole (new infrastructure app)

New dir **`kubernetes/infrastructure/external-dns/`** mirroring the cilium app
pattern (`namespace.yaml`, `repository.yaml`, `release.yaml`,
`kustomization.yaml`):

- **HelmRepository** → `https://kubernetes-sigs.github.io/external-dns/`, chart
  `external-dns`.
- **HelmRelease** values:
  - `provider.name: pihole`
  - `extraArgs`:
    - `--pihole-server=http://pihole-svc.pihole.svc.cluster.local`  *(in-cluster ClusterIP, port 80 per orion `svc-update-ports` patch)*
    - `--source=gateway-httproute`
    - `--domain-filter=${domain}`  *(`orion.norseamerican.com`, Flux postBuild)*
    - `--registry=noop`  *(pihole provider has no TXT ownership registry)*
    - `--policy=upsert-only`  *(start safe; switch to `sync` later)*
  - `env`: `EXTERNAL_DNS_PIHOLE_PASSWORD` from a secret key.
  - `rbac.create: true`; ensure read on `httproutes`/`gateways` + services.
- **SOPS `secret.sops.yaml`** in the `external-dns` namespace with the pihole
  admin password — same value as the existing `pihole-admin` secret
  (`webpassword`), encrypted with the existing age recipient.

### Flux wiring
- New **`kubernetes/clusters/orion/external-dns.yaml`** Flux Kustomization:
  `path: ./kubernetes/infrastructure/external-dns`, `dependsOn: [cilium, pihole]`,
  `decryption.sops`, `postBuild.substitute` `${domain}` + `substituteFrom`
  cluster-settings (mirror `clusters/orion/pihole.yaml`).

---

## Part C — Pi-hole as DNS for all local networks (MANUAL, UDM)

For each UniFi network/VLAN: **Settings → Networks → <net> → DHCP Name Server →
Manual → `10.50.0.232`**. Optionally also point cluster nodes at pihole by
updating the commented nameserver in
`clusters/orion/config/patches/network-vlan.yaml` (currently `1.1.1.1`/`8.8.8.8`)
— Talos-side, optional/secondary.

---

## Critical files
- `kubernetes/infrastructure/cilium/values.yaml` (edit — enable BGP)
- `kubernetes/infrastructure/cilium/policies/bgp-policy.yaml` (new)
- `kubernetes/infrastructure/cilium/kustomization.yaml` (edit)
- `kubernetes/infrastructure/external-dns/{namespace,repository,release,kustomization}.yaml` + `secret.sops.yaml` (new)
- `kubernetes/clusters/orion/external-dns.yaml` (new Flux Kustomization)
- `clusters/orion/docs/unifi-bgp-frr.md` (new — record the applied FRR config)

## Verification
1. **Offline render + lint (no cluster):**
   ```
   bash scripts/flux-build.sh orion
   kustomize build kubernetes/infrastructure/external-dns | kube-linter lint --config .kube-linter.yaml -
   kustomize build kubernetes/infrastructure/cilium       | kube-linter lint --config .kube-linter.yaml -
   ```
   (kind cannot exercise the BGP/Cilium dataplane — validate manifests offline;
   live checks happen post-merge via Flux.)
2. **Merge to `main` → Flux reconciles (no manual apply).** Then read-only:
   ```
   kubectl --context admin@orion -n kube-system exec ds/cilium -- cilium bgp peers
   kubectl --context admin@orion -n kube-system exec ds/cilium -- cilium bgp routes advertised ipv4 unicast
   kubectl --context admin@orion -n external-dns logs deploy/external-dns
   ```
   On UDM: `vtysh -c "show bgp summary"` (peers Established);
   `show ip route bgp` (sees `10.50.0.231/32`, `10.50.0.232/32`).
3. **Cross-VLAN reachability (laptop on VLAN 20):**
   ```
   ping 10.50.0.231
   dig @10.50.0.232 google.com A                      # pihole answers
   dig @10.50.0.232 dns.orion.norseamerican.com A     # ExternalDNS → 10.50.0.231
   ```
4. **Pi-hole UI** → Local DNS shows auto-created `*.orion.norseamerican.com`.
5. After the UDM DHCP-DNS change: renew DHCP on a client and confirm it resolves
   internal names with no explicit `@server`.

## Future work
- **Move UniFi settings to OpenTofu (IaC).** Adopt OpenTofu with the
  `ubiquiti-community/unifi` provider (in the empty `terraform/` dir) to manage
  VLANs, firewall rules, port forwards, and per-network DHCP name servers — this
  would make **Part C** (`DHCP DNS = 10.50.0.232`) declarative instead of manual
  UI clicks. Note: the provider has no BGP/FRR surface, so the UDM BGP config
  (Part A's manual step) remains UI/FRR-managed.

## Risks / notes
- **pihole provider + `--registry=noop`**: no ownership tracking. Start with
  `--policy=upsert-only` so ExternalDNS never deletes hand-made pihole records;
  move to `sync` once confident.
- **eTP=Local advertising**: confirm each VIP is advertised only from the node
  running its pod so failover reconverges via BGP.
- **ASNs** (`65000` UDM / `65001` cluster) are private-range defaults — adjust to
  taste, keep both sides consistent.
- **HA DNS** (a second pihole IP) is out of scope; single resolver `10.50.0.232`.
