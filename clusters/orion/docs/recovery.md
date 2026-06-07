# Recovery Runbook

## etcd snapshot backup

```bash
talosctl -n 10.50.0.11 etcd snapshot /tmp/etcd-$(date +%Y%m%d).snapshot
```

Store the snapshot off-cluster. The `*.snapshot` pattern is gitignored.

## Single CP node loss

If one control-plane node fails permanently (quorum is maintained with 2 of 3):

1. Remove the dead node from etcd:
   ```bash
   talosctl -n 10.50.0.10 etcd remove-member <member-id>
   # Get member IDs: talosctl -n 10.50.0.10 etcd members
   ```
2. Re-image the replacement node with the Talos ISO.
3. Apply the same node's config (no changes to `talconfig.yaml` if it's the same hardware):
   ```bash
   task talos:apply NODE=orion-cp-01 IP=10.50.0.11 INSECURE=true
   ```
4. The node rejoins etcd automatically after receiving config.

## Full cluster recovery from etcd snapshot

1. Apply configs to all nodes (`INSECURE=true`).
2. Bootstrap etcd on one node using the snapshot:
   ```bash
   talosctl -n 10.50.0.11 bootstrap --recover-from /tmp/etcd-<date>.snapshot
   ```
3. Fetch kubeconfig: `task talos:kubeconfig`

## Secret rotation policy

**Do not rotate `talsecret.sops.yaml` on a live cluster.** The cluster CA and etcd CA are embedded in node certificates. Rotating them requires re-imaging all nodes and re-bootstrapping etcd.

The only safe time to generate new secrets is before the first `task talos:bootstrap` call.

If the age key is compromised, re-encrypt `talsecret.sops.yaml` with a new key (via `sops updatekeys`) without changing the underlying Talos secrets.

## Emergency talosconfig recovery

If `clusterconfig/talosconfig` is lost, regenerate it:

```bash
task talos:gen-config
# clusterconfig/talosconfig is recreated with the same certs (from talsecret.sops.yaml)
```
