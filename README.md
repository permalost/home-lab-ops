# home-lab-ops

GitOps repository managing a home-lab Kubernetes cluster using [Flux CD](https://fluxcd.io) and [Talos Linux](https://talos.dev).

## Cluster

| Name | Platform | Status | Hardware |
|------|----------|--------|----------|
| **orion** | Talos Linux | Active | 3x Beelink GK Mini (see `clusters/orion/README.md`) |

`kubernetes/apps/` also holds a set of workloads not yet wired into orion,
kept from a previous k3s cluster (`na`, decommissioned) pending migration.

## Repository Structure

```text
.
├── clusters/orion/          # Talos bare-metal provisioning (pre-Kubernetes layer)
│   ├── patches/              # Per-hardware machineconfig patches
│   ├── clusterconfig/        # Generated machineconfigs (gitignored, contains PKI)
│   └── docs/                # Network topology and runbooks
│
└── kubernetes/              # Flux GitOps layer (in-cluster state)
    ├── bootstrap/           # One-time Flux installer kustomization
    ├── clusters/orion/      # Flux entry point and settings for orion
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
