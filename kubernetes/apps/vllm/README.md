# vllm

OpenAI-compatible inference for the two Hermes agent deployments
(`kubernetes/apps/hermes-sage/`, `kubernetes/apps/hermes-hearth/`), served via
vLLM on `orion-ai-01` (DGX Spark).

Hand-written, not composed from `webapp/base` — GPU scheduling, per-model
resource sizing, and cold-start probes don't fit that template's defaults
(`cpu: 10m` / `memory: 500Mi`, no `runtimeClassName`).

## Components

| Deployment | Image | Model | Role | Endpoint (in-cluster) |
|---|---|---|---|---|
| `vllm-main` | `vllm/vllm-openai:cu130-nightly` | `Qwen/Qwen3.6-27B-FP8` | Hermes main model | `vllm-main.vllm.svc.cluster.local:8000` |
| `vllm-aux` | `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-27-v0.26.0` | `AEON-7/Qwen3.6-35B-A3B-heretic-NVFP4` | Hermes auxiliary model | `vllm-aux.vllm.svc.cluster.local:8000` |

Both are one `nvidia.com/gpu` request each, sharing the single physical GPU via
time-slicing (`kubernetes/infrastructure/nvidia-device-plugin/`, 4 replicas
advertised). Each has its own PVC — they serve different models, so nothing is
shared and no RWX/CephFS storage class is needed (`rook-ceph-block`, RWO, is
enough).

Both the Deployment and Service carry a `model` label (`qwen3.6-27b` /
`qwen3.6-35b-a3b-heretic`) — `kubectl get pods -n vllm -L model` shows what's
running without digging through container args.

Both Deployments run a `clean-stale-models` initContainer (purges any cached
checkpoint that doesn't match what's configured, before the main container
starts — see "PVCs stay right-sized" below). `vllm-aux` also runs a
`wait-for-main` initContainer that blocks until `vllm-main` is healthy — see
"Startup is sequenced" below.

## Why these two models

`Qwen3.6-27B` (dense) leads `Qwen3.6-35B-A3B` (MoE) by 8-11 points on
Terminal-Bench 2.0 and BenchLM's agentic category — the categories closest to
what Hermes actually does — at the cost of ~28-33 tok/s vs ~108 tok/s (NVFP4 +
MTP) for the MoE. Given that gap, `main` runs the agent loop and `aux` absorbs
Hermes's high-volume, low-difficulty auxiliary calls (title generation, context
compression, approval scoring, web summarization) where speed matters more than
the quality edge.

## vllm-aux runs an uncensored checkpoint — read this first

`AEON-7/Qwen3.6-35B-A3B-heretic-NVFP4` is deliberately "abliterated" (safety
refusals stripped, 5/100 refusal rate per its own model card), not a plain
re-quantization of stock Qwen3.6-35B-A3B. This was a deliberate, informed
choice — NVIDIA's official checkpoint hit a real vLLM loader bug on this
hardware (see below) and this was the fix — but it means the model backing
Hermes's `approval` role (see `hermes-sage/config.yaml`,
`hermes-hearth/config.yaml`) currently has no safety guardrails of its own.
Revisit this if that stops being acceptable — e.g. by routing `approval`
specifically back to `vllm-main` instead of `vllm-aux`.

## PVCs stay right-sized — checkpoints don't accumulate

Each PVC (`mainStorageSize: 35Gi`, `auxStorageSize: 35Gi` in
`clusters/orion/vllm.yaml`) is sized for **one** checkpoint plus headroom, not
for holding old ones alongside new. A checkpoint swap once left the old
download (~22GB) sitting on the volume with nothing to reclaim it, filling a
30Gi PVC and crashing the pod mid-download with a disk-full error.

Fix is the `clean-stale-models` initContainer on both Deployments — deletes
any `models--*` cache directory not matching the model about to be served,
every pod start. **Its `KEEP` value must be kept in sync by hand with the
`--model`/`serve` arg in the same file** — no single source of truth links
them, so a checkpoint change needs both updated together, or the
initContainer deletes the checkpoint that's about to be used.

## Startup is sequenced — main first, then aux

`vllm-aux`'s `wait-for-main` initContainer blocks until `vllm-main` reports
healthy before `vllm-aux` starts loading. Time-slicing gives the two zero
memory isolation on the shared GPU (see below) — letting both load at once
once starved `vllm-main` of its GPU memory share mid-startup. Sequencing
keeps their memory peaks from overlapping. One-directional: if `vllm-main` is
ever down, `vllm-aux` waits rather than competing with it for memory, which
is the right failure mode here.

## Known risks — read before deploying

- **`vllm-aux` runs an unaudited third-party image and checkpoint.**
  `ghcr.io/aeon-7/aeon-vllm-ultimate` is a single-maintainer community build
  carrying unmerged upstream vLLM patches, with an explicit warranty
  disclaimer — pinned to a dated tag (not `:latest`, which the project itself
  documents as floating) for reproducibility, but not security-audited by
  anyone. Switched to it because NVIDIA's official
  `nvidia/Qwen3.6-35B-A3B-NVFP4` checkpoint hits a real, currently-open vLLM
  bug on this hardware — a `KeyError` loading MoE expert scale tensors
  ([#44081](https://github.com/vllm-project/vllm/issues/44081),
  [#38980](https://github.com/vllm-project/vllm/issues/38980), both open, no
  fix landed). `r0b0tlab/vllm-v0250-cu130-sm121` was the more conservative
  alternative considered (properly pinned, official checkpoint, no specific
  claim of fixing this bug) — revisit if AEON-7's image proves unreliable.
- **`vllm-main`'s image is still unpinned.** `vllm/vllm-openai:cu130-nightly`
  is a moving tag — whatever's cached on the node from first pull is what
  runs, regardless of what the tag points to upstream now. Confirmed working
  for this checkpoint; unresolved as a general risk. Stock vLLM releases lack
  sm_121 (Blackwell) kernels for aarch64
  ([#36821](https://github.com/vllm-project/vllm/issues/36821), open) — this
  hardware needs the CUDA 13 nightly track.
- **Tool-call parser is `qwen3_coder`, not `hermes`.** Wrong parser → tool
  calls arrive as literal text JSON and Hermes fails silently.
- **`--gpu-memory-utilization` is a fraction of total unified memory**,
  shared by both deployments and the OS. `main` (0.40) + `aux` (0.30) = 0.70,
  under the ~0.80 threshold where GB10 has been reported to freeze
  ([forum report](https://forums.developer.nvidia.com/t/gemma-4-on-dgx-spark-gb10-system-freeze-at-80-utilization-sm-121-kernel-issues/366060)).
  Container memory *limits* matter independently of this fraction —
  `vllm-aux` has been OOMKilled twice (40Gi, then 60Gi); current limits
  (32Gi main / 80Gi aux) leave ~9.67GiB margin against the node's actual
  121.67GiB. `vllm-aux`'s real peak still isn't precisely measured (cgroup
  stats reset on crash) — may need another round.
- **Node taint toleration is confirmed correct.** Live-verified:
  `nvidia.com/gpu=true:NoSchedule`, and `operator: Exists` matches regardless
  of value. Still applied by hand via `kubectl taint`, not tracked in git —
  could drift.
- **Cold start is slow.** Weight download + JIT compile on every start,
  stacked with Kubernetes' `progressDeadlineSeconds` and the Flux
  Kustomization's own `timeout` (both set to a matching ~30-35 min budget —
  see `clusters/orion/vllm.yaml`).
- **DFlash speculative decoding isn't configured for `vllm-aux`.** Needs its
  own unmerged vLLM PR
  ([#40898](https://github.com/vllm-project/vllm/pull/40898)) on top of
  everything else already unproven here.

## Verify

```
kubectl describe node orion-ai-01 | grep -A5 Allocatable   # nvidia.com/gpu: 4
kubectl logs -n vllm deploy/vllm-main   # confirm reported KV cache size matches expectations
kubectl logs -n vllm deploy/vllm-aux
```
