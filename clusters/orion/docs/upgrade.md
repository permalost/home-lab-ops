# Upgrade Runbook

## Safe apply workflow (required before any node change)

**Always run a dry-run and review the diff before applying to any live node.**
Any field appearing in the diff that you didn't intentionally change is a stop-and-investigate signal — do not proceed.

```bash
# 1. Re-render after any patch or talconfig.yaml change
task talos:gen-config

# 2. Schema validation
task talos:validate

# 3. Review what Talos will actually change on every node
task talos:dry-run-all
```

For a pure structural reorganisation (no intentional config changes), the expected
diff is only the removal of deprecated Talos defaults: `rbac`, `stableHostname`,
`apidCheckExtKeyUsage`. **New fields appearing in the diff require a deliberate
decision before proceeding.**

```bash
# 4. Apply one node first, verify it is healthy before rolling the rest
task talos:apply NODE=orion-cp-03 IP=10.50.0.13
# confirm: kubectl get nodes, talosctl etcd members

# 5. Roll remaining nodes one at a time for control-plane nodes;
#    workers can follow after all CPs are healthy
task talos:apply NODE=orion-cp-01 IP=10.50.0.11
task talos:apply NODE=orion-cp-02 IP=10.50.0.12
task talos:apply NODE=orion-w-01  IP=10.50.0.21
task talos:apply NODE=orion-w-02  IP=10.50.0.22
```

## Patch hygiene rules

- **Only set fields that differ from Talos defaults.** If a field isn't in the
  original running config and isn't explicitly needed, don't add it.
- **Migration PRs must be functionally equivalent.** A patch reorganisation
  should produce a minimal diff — only structural changes, not new behaviour.
- **One concern per patch file.** Mixing role config with feature additions makes
  it impossible to isolate which change caused a regression.

## Upgrading Talos

Upgrade one node at a time. For control-plane nodes, confirm etcd quorum
is restored before moving to the next.

```bash
# Drain the node (optional but safer for workers)
kubectl drain orion-cp-01 --ignore-daemonsets --delete-emptydir-data

# Dry-run first to confirm only the installer image changes
task talos:dry-run NODE=orion-cp-01 IP=10.50.0.11

# Upgrade
task talos:upgrade-talos NODE=orion-cp-01 IP=10.50.0.11 IMAGE=ghcr.io/siderolabs/installer:v1.12.1

# Wait for node to rejoin, then uncordon
kubectl uncordon orion-cp-01
```

After all nodes are upgraded, update `talosVersion` in `talconfig.yaml` and re-render:

```bash
task talos:gen-config
task talos:validate
```

## Upgrading Kubernetes

```bash
task talos:upgrade-k8s TO=v1.33.0
```

Talos handles the rolling upgrade of control-plane components and kubelet automatically.

After upgrading, update `kubernetesVersion` in `talconfig.yaml` and re-render.

## Checking current versions

```bash
talosctl version --nodes 10.50.0.11 --endpoints 10.50.0.11
kubectl version
```

## What to do if the apiserver crashes after an apply

1. Check which CP is affected: `kubectl get pods -n kube-system | grep apiserver`
2. Get the crash reason: `kubectl logs -n kube-system kube-apiserver-orion-cp-XX`
3. The fix is almost always to revert the offending patch and re-apply without reboot:
   ```bash
   # Fix the patch file, re-render, re-apply (no reboot needed for static pod changes)
   task talos:gen-config
   talosctl apply-config --nodes <ip> --endpoints <ip> --file clusterconfig/orion-orion-cp-XX.yaml
   ```
4. Controller-manager / scheduler CrashLoopBackOff after apiserver recovery is normal —
   they will self-heal once the 5-minute back-off timer expires.
