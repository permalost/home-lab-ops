# plans

OS auto-upgrade plan for k3s nodes using the [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller). Defines an upgrade `Plan` CR that automatically drains and upgrades nodes to a specified OS image version.

## Configuration

- `upgrade-plan.yaml` — defines the `Plan` CR with the target OS image version and node selector.
- `secret.yaml` — credentials for the upgrade process (SOPS-encrypted).

The OS image version in `upgrade-plan.yaml` must be updated manually when a new version is desired.

## Dependencies

System Upgrade Controller must be installed in the cluster (not managed by this repo — install separately or add to infrastructure).

## Ingress / Endpoints

None.

## Troubleshooting

- **Nodes not upgrading:** Check `kubectl get plans -n system-upgrade` and the System Upgrade Controller pod logs.
- **Upgrade stalled on a node:** The node may have pods that cannot be evicted. Check `kubectl describe plan -n system-upgrade`.
