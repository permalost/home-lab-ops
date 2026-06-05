# pihole

Primary DNS resolver and ad-blocker. Runs as a raw Deployment (no Helm chart) with a LoadBalancer Service for DNS traffic.

## Configuration

- **Namespace:** `pihole`
- DNS configuration in `configMap.yaml`; credentials in `secret.yaml` (SOPS-encrypted).
- Network policy in `pihole-policy.yaml` restricts ingress to DNS (53/UDP, 53/TCP) and the web UI port.
- `pihole-registry.yaml` defines the image source.

## Dependencies

Requires a LoadBalancer IP from MetalLB (na) or Cilium L2 (orion). Operates as the primary cluster DNS alongside `pihole2`.

## Ingress / Endpoints

Web UI exposed via nginx ingress at `dns.${domain}`.

## Troubleshooting

- **DNS queries not resolving:** Check the LoadBalancer Service has an external IP and UDP port 53 is reachable.
- **Ad-block lists not updating:** Gravity update runs on a schedule; trigger manually via the admin UI or `kubectl exec`.
- **Web UI unreachable:** Verify the ingress and that the pod is running (`kubectl -n pihole get pods`).
