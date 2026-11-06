# hermes-agents

Read-only infrastructure agents, one per directory. First agent: `truenas/`, which watches any number of
TrueNAS instances. Its rules, skills and tests live in the separate `hermes-agents` content repository (the
recipe); this directory is only how it runs here. Plan and evidence: `kubernetes/clusters/orion/docs/hermes-agents.md`.

## How it works

- An init container (git-sync, pinned by digest) fetches **one commit** of the recipe repository into an
  `emptyDir` and exits. Hermes mounts it read-only at `/srv/agent-content` and reads its `AGENTS.md` and skills
  in place. Nothing is copied into the agent's home; Hermes holds no Git credential.
- `terminal.cwd` is the agent's directory inside the checkout, so Hermes loads the root `AGENTS.md` and the
  agent's own. `skills.external_dirs` lists the shared and the agent's skill directories.
- The agent's own state (learned skills, memory, sessions) is the PVC at `/opt/data`.
- It reaches the NAS instances through the Gateway, with a **read-only** TrueNAS account per instance. The helper
  allows only read methods, but the account is the real fence.
- Egress is an allowlist (`truenas/network-policy.yaml`): the model endpoints, the in-cluster Forgejo, the NAS
  instances (through the Gateway), and the public internet on ports 80 and 443. Nothing on the cluster or the LAN.
- Approvals are off (the Paperclip gateway cannot answer them). The fences are the read-only NAS account, the
  read-only checkout, no cluster credentials (no service account token), and the network policy.

## Secrets (`truenas/secret.yaml`, SOPS)

| Key | What | Needed |
|---|---|---|
| `API_SERVER_KEY` | Bearer key for the Hermes API. Generated. | yes |
| `FORGEJO_READ_TOKEN` | Token of a read-only account on the in-cluster Forgejo with read access to the recipe repository. | yes: without it the init container fails and the pod does not start |
| `TRUENAS_<ID>_API_KEY` | A read-only TrueNAS API key for instance `<ID>`. Empty means no key. | per instance: the agent starts without it and reports the instance as having no key |

Set a value without opening the file:

```bash
sops set kubernetes/apps/hermes-agents/truenas/secret.yaml '["stringData"]["FORGEJO_READ_TOKEN"]' '"<token>"'
sops set kubernetes/apps/hermes-agents/truenas/secret.yaml '["stringData"]["TRUENAS_BIGNAS_API_KEY"]' '"<key>"'
```

Create the TrueNAS account with the read-only administrator role and nothing more, then confirm a write is
refused before relying on it. Create the Forgejo account as read-only on the one repository. Rotate by
`sops set` and a pod restart.

## Instances

An instance is an id and a URL. Today: `bignas` and `fastnas`, at `https://<id>.${domain}` (the Gateway, trusted
certificate). To add one, in `truenas/`: a URL and key entry in `patches/deploy-add-env.yaml`, the same two names
under `terminal.env_passthrough` in `config/config.yaml` (Hermes strips any variable not named there), a key in
`secret.yaml`, and a `toServices` entry for its NAS Service in `network-policy.yaml` (the Gateway's upstream is
checked against the pod's egress). To drop one, remove them. The agent discovers instances from `TRUENAS_<ID>_URL` at start.

## Changing what the agent runs

- **Recipe content:** change `--ref` in `truenas/patches/deploy-git-sync.yaml` to the new commit, in a PR. The
  pod restarts and fetches it. Hermes caches the skill directories, so a restart is the only way a change applies.
- **Image:** the digest in `truenas/kustomization.yaml` is `v2026.9.24`, the same as the other Hermes pods.
  Check the helper and skills still load before bumping.
- **git-sync:** `v4.8.0`, by digest. It runs as uid 65533 into a root-owned `emptyDir`, so it passes
  `--git-config=safe.directory:/srv/agent-content`; without it git refuses the directory ("dubious ownership").

## Read-only checks after a change

```bash
kubectl -n hermes-agents get pods
kubectl -n hermes-agents logs deploy/hermes-truenas-deploy -c git-sync     # the pinned commit was fetched
kubectl -n hermes-agents exec deploy/hermes-truenas-deploy -- ls /srv/agent-content/current/agents/truenas
```

Never dump the container environment: it holds the keys.

## Troubleshooting

Both failures below happened on the first deploy (2026-11-06) and were fixed as described. All commands are read-only.

### Pod stuck in `Init:CrashLoopBackOff`

```bash
kubectl -n hermes-agents get pods
kubectl -n hermes-agents logs deploy/hermes-truenas-deploy -c git-sync --tail=10
```

- `detected dubious ownership in repository at '/srv/agent-content'` and `too many failures, aborting`: git-sync runs
  as uid 65533 into a root-owned `emptyDir`, and git refuses it. Fix: the init container arg
  `--git-config=safe.directory:/srv/agent-content` in `truenas/patches/deploy-git-sync.yaml` (#305). A healthy run
  ends with `updated successfully` and `exiting after one sync`, `"status":0`.
- Any other error (authentication, unknown ref): check that `FORGEJO_READ_TOKEN` is set and that `--ref` is a commit
  that exists on the in-cluster Forgejo.
- While a pod crash-loops, Flux's `wait` holds the Kustomization on the old revision until its 15-minute timeout,
  then retries. A merged fix can take several minutes to appear.

### `tn_ro.py --check` says `UNREACHABLE ... InvalidStatus`

```bash
kubectl -n hermes-agents exec deploy/hermes-truenas-deploy -c hermes-agents -- sh -c \
  'cd /srv/agent-content/current/agents/truenas/skills/truenas-health && python3 scripts/tn_ro.py --check'
```

`InvalidStatus` means the server answered the WebSocket upgrade with a plain HTTP status. Here it was `403` with the
body `Access denied` and `server: envoy`: the Cilium Gateway's proxy, not the NAS. Confirm on the Cilium pod on the
agent's node:

```bash
kubectl -n cilium exec <cilium pod on that node> -c cilium-agent -- \
  hubble observe --namespace hermes-agents --last 300 -o compact | grep -i 'http-request'
```

`http-request DROPPED (GET https://<nas host>/)` confirms it. Cause: Cilium checks the calling pod's egress policy
against the Gateway's upstream, the NAS Service in `external-endpoints`, as well as the Gateway itself. Fix: one
`toServices` entry per NAS Service on 443 in `truenas/network-policy.yaml` (#306). After it, `--check` returned
real data from both instances. Instances that still fail with another status are a different problem (the NAS
address, key or account).

## Known limits

- Internet access (80 and 443) is a way out as well as a way in: an agent that reads untrusted text (a task, an
  alert, a log line) and can run commands could send what it has read to the internet. What it can read is
  limited by the read-only NAS account, but it is not nothing. Remove the internet rule from the network policy if
  you do not need it; the model, Forgejo and NAS rules do not depend on it.
- Egress allows the Gateway's HTTPS port (the NAS is reached through it, as the runner reaches Forgejo). The NAS
  API key, not the network policy, limits what that reaches. Reaching a NAS directly needs the helper to accept a
  certificate name that differs from the address; the NAS certificate names only `localhost`.
- The root filesystem is writable and the container runs as root with privileges dropped by `PUID`/`PGID`: the
  image's init system needs it (same as the other Hermes pods).
- Hermes cannot save changes to `config.yaml` from its own dashboard (subPath mount). Change it here.
- Not built: the UniFi agent, the scheduled `--check`, Paperclip wiring, and the exporter for learned skills.
