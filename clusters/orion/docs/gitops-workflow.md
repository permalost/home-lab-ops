# GitOps Workflow

This cluster uses a two-layer GitOps model — one layer per domain, each with
different automation levels.

---

## Layer 1: Talos OS (Assisted GitOps)

**Source of truth:** `clusters/orion/talconfig.yaml` + `clusters/orion/patches/`

**Why "assisted" and not fully automated:**

1. Applying Talos machineconfigs touches the OS level and some changes require
   node reboots. A human review gate before apply is intentional.
2. The age decryption key (required to regenerate configs from the encrypted
   `talsecret.sops.yaml`) is never stored in CI — configs are always generated
   locally, never in GitHub Actions.

**Workflow for Talos changes:**

```
edit talconfig.yaml or a patch → open PR
CI validates schema (talhelper validate talconfig)
↓ merge
task talos:gen-config       # regenerate clusterconfig/ locally
task talos:dry-run-all      # review what would change on each node
task talos:apply-all        # apply to all nodes (non-disruptive for most changes)
```

**Version bumps (automated via Renovate):**

Renovate opens PRs weekly to bump `talosVersion` and `kubernetesVersion` together.
Talos and Kubernetes versions must be bumped as a pair — see the compatibility
matrix: https://www.talos.dev/latest/introduction/support-matrix/

After the Renovate PR merges, run `task talos:gen-config && task talos:apply-all`.
Kubernetes upgrades require an additional `task talos:upgrade-k8s` step.

---

## Layer 2: Kubernetes workloads (Full GitOps via FluxCD)

**Source of truth:** `kubernetes/` directory, branch `main`

FluxCD polls GitHub every minute and reconciles any drift automatically. Changes
merged to `main` appear in the cluster within 1–20 minutes depending on the
Kustomization interval.

**Version bumps (automated via Renovate):**

- **Cilium:** Renovate opens PRs to bump the pinned chart version in
  `kubernetes/infrastructure/cilium/release.yaml`. After merge, Flux reconciles
  the HelmRelease automatically — no manual step needed.
- **Flux itself:** Updated hourly by the `flux-upgrade` GitHub Actions workflow.

---

## CI checks on every PR

| Job | What it validates |
|---|---|
| `pre-commit` | Trailing whitespace, YAML syntax, secret detection, gitleaks |
| `Validate manifests` | kubeconform, kube-linter, talhelper schema, offline Flux render |
| `Validate Talos config` | talhelper schema check only (fast, parallel) |

---

## Bootstrap (new cluster)

See [`bootstrap.md`](bootstrap.md) for the ordered sequence including
the mandatory pre-Flux Cilium install step.
