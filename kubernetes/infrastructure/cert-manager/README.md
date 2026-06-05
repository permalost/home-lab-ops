# cert-manager

Issues and renews TLS certificates via Let's Encrypt using Cloudflare DNS-01 challenges. Provides `ClusterIssuer` resources for both staging and production.

## Configuration

- **Chart:** `cert-manager/cert-manager` (see `release.yaml` for pinned version)
- **Namespace:** `cert-manager`
- **Values source:** HelmRelease inline (`installCRDs: true`)

Two cluster issuers are defined in `issuers/`:
- `letsencrypt-staging` — for testing; produces untrusted certificates
- `letsencrypt-prod` — for real certificates; rate-limited

Cloudflare API token is stored in `secret.yaml` (SOPS-encrypted). The issuers reference this secret for DNS-01 challenge resolution.

## Dependencies

None. Can be applied independently of other components.

## Ingress / Endpoints

No direct ingress. Other components reference these issuers via `cert-manager.io/cluster-issuer` annotations.

## Troubleshooting

- **Certificate stuck in `Pending`:** Check `kubectl describe certificaterequest -n <ns>` and look at the challenge object for DNS-01 propagation errors.
- **Cloudflare auth error:** Verify the API token in `secret.yaml` has `Zone:Read` and `DNS:Edit` permissions.
- **Rate limit hit:** Switch to the `letsencrypt-staging` issuer temporarily; staging has much higher limits than production but is still rate-limited.
