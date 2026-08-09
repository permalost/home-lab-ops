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

## Known risks — read before deploying

- **`vllm-aux` runs an unaudited third-party image.** `ghcr.io/aeon-7/aeon-vllm-ultimate`
  is a single-maintainer community build carrying unmerged upstream vLLM
  patches, with an explicit warranty disclaimer. It's pinned to a dated tag
  (not `:latest`, which the project itself documents as floating) for
  reproducibility, but the image itself hasn't been security-audited by
  anyone. Switched to it because NVIDIA's official `nvidia/Qwen3.6-35B-A3B-NVFP4`
  checkpoint hit a real, currently-open vLLM bug on this hardware — a
  `KeyError` loading MoE expert scale tensors
  ([vLLM #44081](https://github.com/vllm-project/vllm/issues/44081),
  [#38980](https://github.com/vllm-project/vllm/issues/38980), both open, no
  fix landed). r0b0tlab's `vllm-v0250-cu130-sm121` was the more conservative
  alternative considered (properly pinned, official checkpoint, but no
  specific claim of fixing this bug) — revisit that if the AEON-7 image turns
  out to be unreliable.
- **`vllm-main`'s image is still unpinned.** `vllm/vllm-openai:cu130-nightly`
  is a moving tag, not a reproducible pin — whatever's cached on the node from
  first pull is what actually runs, regardless of what the tag currently
  points to upstream. Confirmed working for `vllm-main`'s checkpoint
  specifically; unresolved as a general risk. Stock vLLM release images lack
  sm_121 (Blackwell) kernels for aarch64
  ([vLLM #36821](https://github.com/vllm-project/vllm/issues/36821), open) —
  this hardware needs the CUDA 13 nightly track
  ([vLLM's own DGX Spark writeup](https://vllm.ai/blog/2026-06-01-vllm-dgx-spark)
  confirms this works in general).
- **Tool-call parser is `qwen3_coder`, not `hermes`.** Wrong parser → tool calls
  arrive as literal text JSON and Hermes fails silently.
- **`--gpu-memory-utilization` is a fraction of total unified memory**, shared
  by both deployments, the OS, and every other pod. `main` (0.40) + `aux` (0.30)
  = 0.70 total, deliberately under the ~0.80 threshold where GB10 has been
  reported to freeze
  ([forum report](https://forums.developer.nvidia.com/t/gemma-4-on-dgx-spark-gb10-system-freeze-at-80-utilization-sm-121-kernel-issues/366060)).
  Don't raise either without lowering the other to compensate. Separately,
  confirmed live that container memory *limits* also matter independently of
  this fraction — `vllm-aux` was genuinely OOMKilled once at its old 40Gi
  limit (see git history on `deployment-aux.yaml`); current limits (32Gi
  main / 60Gi aux) are based on `vllm-main`'s measured real peak (~23GB), not
  just guesswork, but `vllm-aux`'s footprint under the new image/checkpoint
  is still unconfirmed.
- **Node taint toleration is confirmed correct.** Live-verified: the taint is
  `nvidia.com/gpu=true:NoSchedule`, and `operator: Exists` matches regardless
  of value — no longer an open risk, but still applied by hand via `kubectl
  taint` and not tracked in git, so it could drift.
- **Cold start is slow.** First run downloads weights to the PVC (tens of GB)
  plus JIT compile on every start; this stacks with Kubernetes' own
  `progressDeadlineSeconds` (separate from the `startupProbe` — both are set
  to a matching 30-minute budget now, confirmed live that the K8s-level
  default of 10 minutes fires independently and marks the rollout `Failed`
  well before a legitimately slow model load finishes).
- **DFlash speculative decoding is deliberately not configured for `vllm-aux`.**
  It needs its own unmerged vLLM PR
  ([#40898](https://github.com/vllm-project/vllm/pull/40898)) on top of
  everything else already unproven here — get the base serving path working
  first before adding it back.

## Verify

```
kubectl describe node orion-ai-01 | grep -A5 Allocatable   # nvidia.com/gpu: 4
kubectl logs -n vllm deploy/vllm-main   # confirm reported KV cache size matches expectations
kubectl logs -n vllm deploy/vllm-aux
```
