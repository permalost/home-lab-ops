# pihole2

Secondary DNS resolver — HA pair to `pihole`. Clients should use both pihole and pihole2 as DNS servers for redundancy.

## Configuration

- **Namespace:** (shares or is adjacent to pihole — see `kustomization.yaml`)
- Environment overrides in `env/` directory.
- Patches in `patches/` for resource customization.
- LoadBalancer definition in `loadbalancer.yaml` for the DNS service.
- Credentials in `secret.yaml` (SOPS-encrypted).

## Dependencies

Same as `pihole`. Both instances should be kept in sync (ad-list updates, upstream DNS config).

## Ingress / Endpoints

DNS service via LoadBalancer. No web UI ingress configured (admin via the primary pihole).

## Troubleshooting

- **DNS split-brain between pihole and pihole2:** Ensure both are using the same upstream resolvers and block lists. Gravity sync or manual sync may be needed.
