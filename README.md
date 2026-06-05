# home-lab-ops

GitOps repository managing two home-lab Kubernetes clusters using [Flux CD](https://fluxcd.io) and [Talos Linux](https://talos.dev).

## Clusters

| Name | Platform | Status | Hardware |
|------|----------|--------|----------|
| **orion** | Talos Linux | Active (in progress) | 3x Beelink GK Mini (see `clusters/orion/README.md`) |
| **na** | k3s (k3sup) | Active (being replaced by orion) | — |

## Repository Structure

```
.
├── clusters/orion/          # Talos bare-metal provisioning (pre-Kubernetes layer)
│   ├── config/patches/      # Per-hardware machineconfig patches
│   ├── rendered/            # Generated full machineconfigs (gitignored secrets)
│   └── docs/                # Network topology and runbooks
│
└── kubernetes/              # Flux GitOps layer (in-cluster state)
    ├── bootstrap/           # One-time Flux installer kustomization
    ├── clusters/            # Per-cluster Flux entry points and settings
    │   ├── orion/           # orion cluster (Talos)
    │   └── na/              # na cluster (k3s)
    ├── infrastructure/      # Shared HelmRelease/Kustomize components
    └── apps/                # Workload deployments
```

The two layers are independent: `clusters/` provisions the OS and nodes; `kubernetes/` is everything Flux manages once the cluster is running.

## Prerequisites

Install tooling via Homebrew:

```sh
task gen:tools   # runs brew bundle
```

Set up your age key for SOPS secret decryption:

```sh
task flux:sops-create   # generates a new key at ~/.config/sops/age/keys.txt
```

## Key Workflows

| Task | Command |
|------|---------|
| Validate all manifests locally | `task gen:validate` |
| Bootstrap Flux into a cluster | `task flux:install` |
| Force Flux reconciliation | `task flux:reconcile` |
| Restart failed HelmReleases | `task flux:hr-restart` |
| Install tools | `task gen:tools` |

Run `task` (no arguments) to list all available tasks.

## Secrets

Secrets are encrypted with [SOPS](https://github.com/getsentry/sops) + [age](https://age-encryption.org). The `.sops.yaml` at the repo root defines which files and fields are encrypted. Never commit unencrypted secrets — the pre-commit hooks (`forbid-secrets`, `gitleaks`, `detect-private-key`) will block the commit.

## Validation

Pre-commit hooks run automatically on every commit. To run the full validation suite manually:

```sh
task gen:validate
```

This runs `kubeconform` (schema validation against K8s 1.31 + Flux CRDs) and `kube-linter` (semantic best-practice checks). The same checks run in CI on every push and PR.

## Further Reading

- [Orion cluster setup and operations](clusters/orion/README.md)
- [Kubernetes GitOps structure](kubernetes/README.md)
