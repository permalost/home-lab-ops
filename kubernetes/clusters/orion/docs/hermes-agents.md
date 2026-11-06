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
| The Hermes image ships Python 3.13.5 with `websockets` 15.0.1 in `/opt/hermes/.venv`. | installed image |
| Hermes passes a child process (the terminal tool, scheduled scripts) only the environment variables it is told to: a skill's `required_environment_variables`, or `terminal.env_passthrough` in `config.yaml` (exact names). Names on Hermes's own block list can never be passed. | Hermes docs at the deployed tag; installed image |
| Defaults in the image: `restart_drain_timeout: 0` (a restart cuts live conversations), `cron_drain_timeout: 30`. Curator: runs every 7 days, marks skills stale after 14 idle days, archives after 30, consolidation off; it touches only agent-created skills and skips pinned ones. | installed image (`config_defaults.py`, `agent/curator.py`) |
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
| `.../truenas/config/config.yaml` | `terminal.cwd`, `skills.external_dirs`, memory settings, and **`terminal.env_passthrough`** listing the exact `TRUENAS_<ID>_URL`, `TRUENAS_<ID>_API_KEY` (and optional `TRUENAS_<ID>_CA_FILE`) names for every instance. Without it Hermes strips them and the helper sees no instances. Also `curator.archive_after_days` raised (an infrastructure agent may go a month without an incident and would otherwise lose that learned skill) and a non-zero `restart_drain_timeout` (about 60 seconds). Key names confirmed in the image. |
| `.../truenas/cronjob-check.yaml` | The scheduled check, see below. |
| `.../truenas/secret.yaml` (SOPS) | `API_SERVER_KEY`; for each TrueNAS instance `TRUENAS_<ID>_URL` and `TRUENAS_<ID>_API_KEY` (`<ID>` is chosen here; the recipe handles any number); a read-only Forgejo deploy token for the init container only. |
| `.../truenas/network-policy.yaml` | `CiliumNetworkPolicy`: egress to DNS, the model endpoint, each TrueNAS instance, and Forgejo. Nothing else. |
| `.../truenas/patches/deploy-security.yaml` | Same container override as `hermes-hearth`/`hermes-dev` (the image needs root for s6), plus `automountServiceAccountToken: false` and resource limits. |

The recipe's `tn_ro.py` discovers instances from `TRUENAS_<ID>_URL`. One key per instance, never shared. The first slice can configure just one.

### Scheduled check (outside Hermes)

The recipe's `tn_ro.py --check` prints nothing and exits 0 when every instance is clear, exits 1 with one line per problem, and exits 2 when an instance could not be checked or none is configured. Schedule it as a Kubernetes `CronJob`, not as a Hermes cron job:

- Hermes scheduled scripts must live in its writable home (paths resolving outside are rejected), which conflicts with reading the recipe in place, and they stop if the Hermes process stops.
- The CronJob reuses the agent's pinned image and its git-sync init container at the same commit, runs `/opt/hermes/.venv/bin/python3 .../tn_ro.py --check` with the agent's Secret, and needs no model.
- Alert on a failed Job (exit 1 or 2) and on **no successful Job within two intervals**. A silent miss looks exactly like a quiet healthy night, and one operator lost six days to that.
- Prove each alert fires once (a wrong key, a stopped instance), then restore it.

### UniFi agent: one MCP server per controller

The recipe's `agents/unifi/mcp/README.md` is the contract; this section is how to meet it here. The server is
`sirkirby/unifi-mcp` (Network server), at the release pinned in the recipe's `agents/unifi/mcp/PIN`. Its behavior
below is from its docs and manifest and has not been run against our controller.

- **One Deployment per controller**, one process per container, with a ClusterIP Service. Hermes reaches it over HTTP, so the server needs `UNIFI_MCP_HTTP_ENABLED=true` and a bearer token of at least 32 characters (`UNIFI_MCP_HTTP_AUTH_TOKEN`, from a mounted Secret, `_FILE` form). Hermes sends the token in a header; `${VAR}` substitution applies to MCP headers.
- **Image pinned by digest.** The project releases several times a day, so pin and re-check on every bump.
- **Settings from the contract:** `UNIFI_TOOL_REGISTRATION_MODE=eager`, `UNIFI_META_TOOLS_ENABLED=false`, `UNIFI_ENABLED_TOOLS` set to the names in the recipe's `read-tools.txt`, `UNIFI_POLICY_CREATE`, `UPDATE` and `DELETE` set to `false`, `UNIFI_TOOL_PERMISSION_MODE=confirm`, `UNIFI_AUTO_CONFIRM=false`, redaction left on, no `UNIFI_API_KEY`.
- **The tool list is a ConfigMap** built from the recipe's `read-tools.txt` at the pinned recipe commit, with a CI check that the two match. Kustomize cannot read a file from another repository, so a copy is unavoidable; the check is what keeps it honest. Not yet built.
- **Login:** a dedicated local controller account with the **View Only** role (not a cloud SSO account, not one that needs MFA), password from a mounted Secret (`UNIFI_PASSWORD_FILE`).
- **TLS:** verification on, with the controller's certificate pinned (`UNIFI_VERIFY_SSL=true`, `UNIFI_SSL_FINGERPRINT`). Never disable verification.
- **Hermes config** for each controller: `mcp_servers.<id>` with the Service URL, the token header, `tools.include` set to the same names, and resource and prompt wrappers off.
- **Network policy:** the server pod accepts traffic only from its Hermes pod and reaches only its controller and DNS. The Hermes pod reaches the server and the usual model endpoint.
- **Alerting is not the agent's job.** Routine UniFi monitoring is UnPoller with Prometheus and Alertmanager, tracked separately. The agent investigates after an alert.

Checks that need a real controller (recipe design 0001, T14 to T18): the View Only login works and a write is
refused; a mutating tool is absent from the tool list and calling it fails; the policy gates deny when set; the
context cost of the full list is acceptable; device state codes against a real, owner-approved upgrade.

### Runbooks the agents write

Agents save draft runbooks as local skills after the owner confirms an incident is resolved (recipe skill
`runbook-authoring`). Learned skills live in each agent's data volume, so:

- the curator archives an agent-created skill idle for 30 days by default. A runbook for a rare incident would
  vanish. Raise `curator.archive_after_days` well past a year, or pin the runbooks, and prefer that over
  disabling the curator (the image's defaults are in the evidence table above);
- `skills.write_approval` stays off: drafts are saved at once and reach shared files only through a reviewed pull
  request from the exporter (not built yet);
- the data volume is where runbooks live until promoted, so it is covered by the volume restore drill below;
- a runbook is instructions future sessions will follow; promotion by reviewed pull request is the gate.

### Credentials (created here, not in the recipe repo)

- A read-only TrueNAS user and API key **per instance** (the UI role is "Readonly Admin"; the role id is reported as `READONLY_ADMIN` but should be confirmed on each version). Not the existing maintenance account.
- A read-only Forgejo deploy token for the recipe repo.
- A **View Only** local account per UniFi controller, and its certificate fingerprint for pinning.
- Optional per instance: the instance's certificate as a CA file (mounted, named by `TRUENAS_<ID>_CA_FILE`) if it uses a self-signed certificate. Certificate checks stay on; there is no insecure option.
- Kill switch: revoke the instance's key on the NAS. That works even if the cluster is unreachable. Removing the agent is then a normal PR, since `kubectl` is read-only here.
- Deliver through SOPS for now. To use ESO later, store the machine-account tokens first (`task bitwarden:token`). The `bitwarden-orion` store is usable from any namespace and reads one shared project; a dedicated store and project limited to the `hermes-agents` namespace (like `bitwarden-paperclip`) would keep agents' secrets apart from other apps.

## Still unknown, checked after deploy (not by hand-made test pods)

| Item | Why it matters |
|---|---|
| Can capabilities be dropped further than `hermes-hearth` does? | Tighter container security. |
| Does git-sync's worktree contain a `.git` path where Hermes looks for the repo root? Hermes only checks that a `.git` path exists in a parent directory (it does not run git). | The shared and per-agent `AGENTS.md` hierarchy depends on it. |
| What happens when Forgejo is down at pod start? | Decides whether to move to an image built from the recipe. |
| Does the `$HERMES_HOME/SOUL.md` link resolve? | Identity without copying. |
| TrueNAS version, role ids, and whether a key inherits the user's read-only role. | Needs the new accounts. Negative test: a write method must be denied by the NAS itself. |
| Does `auth.login_ex` replace `auth.login_with_api_key` on our versions? The official TrueNAS MCP uses `login_ex`. | The helper uses the older call until this is checked. |
| Which snapshot method names exist on each version, and do the four newly added read methods (certificates, interfaces, boot environments, scrub tasks) exist? | Sources disagree for 25.04; a missing method just shows as unavailable. |
| Do the environment variables reach the helper through the gateway after the passthrough entries are added, and not without them? | Test T10 in the recipe. |

## Rollback

- Revert the implementation PR. Flux prunes the namespace objects.
- The PVC uses `reclaimPolicy: Delete`. If learned skills matter, copy `$HERMES_HOME` out first.
- Content rollback: move the `--ref` SHA back and roll the pod.
- Revoke each TrueNAS key and user, and the Forgejo deploy token.
- Existing Hermes instances and Paperclip are untouched, so nothing to roll back there.
- After deploying, watch the pod's restart count over a window longer than the restart interval; a short check can pass inside an up-window.
- Drill a restore of the agent's data volume before relying on it. A copy that was never restored is not a backup.
