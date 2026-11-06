# Hermes agents: cluster evidence and implementation plan

The Hermes agent fleet (a TrueNAS agent, later a UniFi agent) is split in two:

- **Recipe**: the `hermes-agents` content repo on the in-cluster Forgejo. Rules (`AGENTS.md`), skills, and tests. It knows nothing about this cluster.
- **Implementation**: this repo. Pods, the pinned checkout, config, network policy, secrets, credentials.

This page holds what the implementation needs: facts about the cluster, the plan, and what is still unknown. Status: **proposed, nothing here is deployed.** Facts were read on 2026-11-05 from `origin/main` and the live cluster with read-only commands.

## What exists today

| Fact | Where |
|---|---|
| Three Hermes instances: `hermes-hearth`, `hermes-sage`, `hermes-dev`. All run `nousresearch/hermes-agent:v2026.9.24` (Hermes Agent v0.21.5), pinned by tag, not digest. | `kubernetes/apps/hermes-*/kustomization.yaml`, live pods |
| Running image digest for that tag: `sha256:fca358f12efd65bfaaca05884166f15c0e2788375ca30d77061ac1ebc96452b7`. | live pod `imageID` |
| Each instance is Kustomize on `webapp/base`, args `[gateway, run]`, data on a 5Gi RWO `rook-ceph-block` PVC at `/opt/data`. `HERMES_HOME` is `/opt/data` (set by the image). | `kubernetes/clusters/orion/hermes-*.yaml`, live pod |
| The image declares root and boots under s6, then drops to `PUID`/`PGID`. Pod level: `runAsNonRoot: true`, `seccompProfile: RuntimeDefault` (from `webapp/base`). Container override: `allowPrivilegeEscalation: false`, `runAsNonRoot: false`, `readOnlyRootFilesystem: false`. | `kubernetes/apps/hermes-hearth/patches/deploy-security-context.yaml` and its comment |
| No Pod Security labels and no NetworkPolicy in any Hermes or Paperclip namespace. The only Cilium policy is `forgejo-runner/runner-egress`. | live namespaces and policies |
| One StorageClass, `rook-ceph-block`, `reclaimPolicy: Delete`. | live |
| Hermes config is a generated ConfigMap mounted by `subPath`. Skills come from a second ConfigMap mounted as a directory at `skills.external_dirs`. | `kubernetes/apps/hermes-hearth/kustomization.yaml` |
| `hermes-hearth` ships a TrueNAS skill whose helper can create snapshots (a write). The new TrueNAS agent must not reuse it as is; the recipe repo has a read-only version. | `kubernetes/apps/hermes-hearth/skills/truenas/` |
| `hermes-dev` is the closest pattern for Paperclip: API on 8642 behind an HTTPS route, `approvals.mode: "off"`, minimal toolsets, one scoped credential. | `kubernetes/apps/hermes-dev/README.md` |
| Paperclip `2026.1023.0` ships both Hermes adapters. `hermes_gateway` is a deprecated shim for `@paperclipai/hermes-paperclip-adapter` 0.3.1; the adapter type name stays `hermes_gateway`. Plain HTTP to a non-loopback host is refused, so use HTTPS. | Paperclip pod `/app/packages/adapters/`; `hermes-dev` README |
| Flux: source, kustomize, helm and notification controllers only (no image automation). One `GitRepository`, `flux-system`, pointing at this repo on GitHub. Nothing points Flux at Forgejo. | live `flux-system` |
| Secrets today: SOPS (age). External Secrets Operator is installed with two `ClusterSecretStore`s, but both report `InvalidProviderConfig` because their access tokens are not stored yet, so ESO is not usable until that is done. | `kubernetes/infrastructure/external-secrets/README.md`, live stores |
| The `hermes-agents` namespace does not exist. | live |

Process note: read this repo from `origin/main` or the live cluster, not a long-lived local checkout. An earlier survey used a stale checkout and got the image tag, the security context, and the External Secrets facts wrong.

## Decisions

1. **New pods beside the existing ones.** `hermes-hearth`, `hermes-sage` and `hermes-dev` are not changed. Retiring the TrueNAS and UniFi duties of `hermes-hearth` is a separate decision.
2. **One shared namespace, `hermes-agents`, isolation at pod level.** Per agent: its own Secret, ServiceAccount (token not mounted), PVC, and `PUID`/`PGID`. A pod mounts only its own Secret. Caveat: anyone with namespace-wide `get secrets` can read every agent's Secret. No agent gets that.
3. **Read in place, no copies.** An init container checks out the recipe repo at a pinned commit SHA into an `emptyDir`. The Hermes container mounts it read-only. `terminal.cwd` points at the agent's directory, `skills.external_dirs` at its skill directories. Hermes gets no Git credentials. Only the PVC is writable (learned skills, memory, sessions).
4. **`SOUL.md`**: Hermes reads it only from `$HERMES_HOME/SOUL.md`. Link it from there to the checkout; do not copy. Whether the link resolves is untested. Skip until there is an identity worth writing (Hermes seeds a default).
5. **Pin by digest as well as tag** (the digest is above).

## Implementation plan (one PR, after the recipe content is merged)

| File | Purpose |
|---|---|
| `kubernetes/clusters/orion/hermes-agents.yaml` | Flux Kustomization, same shape as `hermes-hearth.yaml`; own `storageSize`. |
| `kubernetes/apps/hermes-agents/namespace.yaml` | Namespace. |
| `kubernetes/apps/hermes-agents/truenas/` | `webapp/base` + `pvc` component, image pinned by digest, args `[gateway, run]`, `PUID`/`PGID` distinct per agent. |
| `.../truenas/patches/deploy-git-sync.yaml` | Init container (pinned git-sync tag, one-time mode, `--ref=<sha>`), `emptyDir`, read-only mount in the Hermes container. Clone from the in-cluster Forgejo service, not its public address. |
| `.../truenas/config/config.yaml` | `terminal.cwd`, `skills.external_dirs`, memory settings. Key names confirmed in the image (`skills.external_dirs` defaults to `[]`, `skills.guard_agent_created` to `False`). |
| `.../truenas/secret.yaml` (SOPS) | `API_SERVER_KEY`; for each TrueNAS instance `TRUENAS_<ID>_URL` and `TRUENAS_<ID>_API_KEY` (`<ID>` is chosen here; the recipe handles any number); a read-only Forgejo deploy token for the init container only. |
| `.../truenas/network-policy.yaml` | `CiliumNetworkPolicy`: egress to DNS, the model endpoint, each TrueNAS instance, and Forgejo. Nothing else. |
| `.../truenas/patches/deploy-security.yaml` | Same container override as `hermes-hearth`/`hermes-dev` (the image needs root for s6), plus `automountServiceAccountToken: false` and resource limits. |

The recipe's `tn_ro.py` discovers instances from `TRUENAS_<ID>_URL`. One key per instance, never shared. The first slice can configure just one.

### Credentials (created here, not in the recipe repo)

- A read-only TrueNAS user and API key **per instance** (the UI role is "Readonly Admin"; the role id is reported as `READONLY_ADMIN` but should be confirmed on each version). Not the existing maintenance account.
- A read-only Forgejo deploy token for the recipe repo.
- Deliver through SOPS for now. To use ESO later, store the machine-account tokens first (`task bitwarden:token`). The `bitwarden-orion` store is usable from any namespace and reads one shared project; a dedicated store and project limited to the `hermes-agents` namespace (like `bitwarden-paperclip`) would keep agents' secrets apart from other apps.

## Still unknown, checked after deploy (not by hand-made test pods)

| Item | Why it matters |
|---|---|
| Can capabilities be dropped further than `hermes-hearth` does? | Tighter container security. |
| Does git-sync's worktree contain a `.git` path where Hermes looks for the repo root? Hermes only checks that a `.git` path exists in a parent directory (it does not run git). | The shared and per-agent `AGENTS.md` hierarchy depends on it. |
| What happens when Forgejo is down at pod start? | Decides whether to move to an image built from the recipe. |
| Does the `$HERMES_HOME/SOUL.md` link resolve? | Identity without copying. |
| TrueNAS version, role ids, and whether a key inherits the user's read-only role. | Needs the new accounts. Negative test: a write method must be denied by the NAS itself. |

## Rollback

- Revert the implementation PR. Flux prunes the namespace objects.
- The PVC uses `reclaimPolicy: Delete`. If learned skills matter, copy `$HERMES_HOME` out first.
- Content rollback: move the `--ref` SHA back and roll the pod.
- Revoke each TrueNAS key and user, and the Forgejo deploy token.
- Existing Hermes instances and Paperclip are untouched, so nothing to roll back there.
