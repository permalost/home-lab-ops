# weave-gitops

Web UI for Flux CD — browse Kustomizations, HelmReleases, GitRepositories, and reconciliation status without using kubectl.

## Configuration

- **Chart:** `weaveworks/weave-gitops` (latest)
- **Namespace:** `flux-system`
- **Values source:** HelmRelease inline

Admin credentials: username `admin`, bcrypt-hashed password stored inline in the HelmRelease `values`. To change the password, generate a new bcrypt hash locally and update `passwordHash`:

```sh
htpasswd -nbBC 10 "" "your-password" | tr -d ':\n' | sed 's/$2y/$2a/'
# or: python3 -c "import bcrypt; print(bcrypt.hashpw(b'your-password', bcrypt.gensalt(rounds=10)).decode())"
```

Do not use online bcrypt tools — they receive your plaintext password.

Ingress uses `ingressClassName: nginx` with cert-manager TLS (`letsencrypt-prod`).

## Dependencies

nginx ingress controller and cert-manager must be running for the UI to be accessible externally.

## Ingress / Endpoints

UI is available at `weave.${domain}` (HTTPS via cert-manager).

## Troubleshooting

- **Login fails:** Verify the `passwordHash` in the HelmRelease values matches the password you're using.
- **Cert not issued:** Check the `Certificate` object in `flux-system` namespace and cert-manager logs.
- **UI shows stale reconciliation state:** Weave GitOps polls Flux; it is eventually consistent and may lag by a minute.
