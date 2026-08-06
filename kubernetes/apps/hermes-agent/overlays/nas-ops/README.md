# hermes-agent/overlays/nas-ops

The first Hermes Agent profile: observes and — within a narrow, RBAC-enforced
allowlist — acts on the two TrueNAS boxes. Extends `../../base`
(image, ports, probes, volumes) and adds this profile's secrets and TrueNAS
API-key env injection.

Every Hermes profile shares one `hermes` namespace (created separately —
see `../../namespace.yaml` — not by this overlay), so this overlay's only
job for avoiding collisions with other profiles is `namePrefix: nas-ops-`
(applies to the Deployment/Service/PVC from `../../base`) plus naming its
own Secret so it lands as `nas-ops-secrets` after that prefix is applied.

Persona (`SOUL.md`) and non-secret config (`config.yaml`) live in the
private [`permalost/hermes-profiles`](https://github.com/permalost/hermes-profiles)
repo (`nas-ops/` directory), pulled in as an `nas-ops-config` ConfigMap by a
separate Flux Kustomization — see `kubernetes/clusters/orion/hermes-nas-ops.yaml`
(two Kustomization docs: `hermes-nas-ops-config` from the `hermes-profiles`
source, `hermes-nas-ops` from this repo, the latter depending on the former;
both set the same `appName: nas-ops` substitution value so the
independently-built ConfigMap name and the Deployment's reference to it
agree).

## Status: skeleton only — not yet functional

Everything here builds and would reconcile, but three real-world pieces are
still placeholders, deliberately not guessed at:

1. **TrueNAS API keys.** `secret.sops.yaml` ships with
   `TRUENAS_READ_API_KEY` / `TRUENAS_WRITE_API_KEY` set to obvious
   placeholder strings. To fill in: on both TrueNAS boxes, create a
   service-account user with the `READONLY_ADMIN` role (read key) and a
   second with a **custom privilege** built from individual roles covering
   only: kick off a scrub, run a SMART test, dismiss a stale alert, prune
   snapshots per existing retention policy (write key) — build this custom
   privilege against the live role catalog on your actual TrueNAS version,
   don't assume role names from documentation. Generate an API key for
   each, then:
   ```sh
   sops --decrypt --in-place kubernetes/apps/hermes-agent/overlays/nas-ops/secret.sops.yaml
   # edit the two REPLACE_ME_ values
   sops --encrypt --in-place kubernetes/apps/hermes-agent/overlays/nas-ops/secret.sops.yaml
   ```

2. **The dedicated model box.** Doesn't exist yet. Once it's built and
   running Ollama/llama.cpp, edit `nas-ops/config.yaml` in the
   **private** `hermes-profiles` repo: `model.base_url` and
   `model.default`.

3. **TrueNAS MCP server sidecars.** `config.yaml`'s `mcp_servers` block
   points at `localhost:3001`/`localhost:3002`, expecting two sidecar
   containers in this Deployment (one per trust level, one image —
   `hongkongkiwi/truenas-master-mcp` is the current best candidate) that
   aren't deployed yet. This needs the exact CLI/env var contract of
   whichever MCP server image you land on confirmed against its actual
   `--help`/README before writing the container spec — not guessed from a
   web search summary. Add it as a patch in this overlay's
   `kustomization.yaml` once confirmed.

Until all three are real, this profile's pod will start (image pulls,
mounts succeed) but the agent won't be able to reach a model or do
anything useful.
