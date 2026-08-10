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
| `vllm-aux` | `vllm/vllm-openai:cu130-nightly` | `Qwen/Qwen3.6-35B-A3B-FP8` | Hermes auxiliary model | `vllm-aux.vllm.svc.cluster.local:8000` |

Both official checkpoints, same stock image — no third-party image/checkpoint
in the loop (see "History" below for why that wasn't always true).

Both are one `nvidia.com/gpu` request each, sharing the single physical GPU via
time-slicing (`kubernetes/infrastructure/nvidia-device-plugin/`, 4 replicas
advertised). Each has its own PVC — they serve different models, so nothing is
shared and no RWX/CephFS storage class is needed (`rook-ceph-block`, RWO, is
enough).

Both the Deployment and Service carry a `model` label (`qwen3.6-27b` /
`qwen3.6-35b-a3b`) — `kubectl get pods -n vllm -L model` shows what's running
without digging through container args.

Both Deployments run a `clean-stale-models` initContainer (purges any cached
checkpoint that doesn't match what's configured, before the main container
starts — see "PVCs stay right-sized" below). `vllm-aux` also runs a
`wait-for-main` initContainer that blocks until `vllm-main` is healthy — see
"Startup is sequenced" below.

## Why these two models

`Qwen3.6-27B` (dense) leads `Qwen3.6-35B-A3B` (MoE) by 8-11 points on
Terminal-Bench 2.0 and BenchLM's agentic category — the categories closest to
what Hermes actually does — but the MoE model is substantially faster per
token (only ~3B params active per forward pass). `main` runs the agent loop;
`aux` absorbs Hermes's high-volume, low-difficulty auxiliary calls (title
generation, context compression, approval scoring, web summarization) where
speed matters more than the quality edge.

## History — why vllm-aux isn't running NVIDIA's own NVFP4 checkpoint

NVIDIA's official `nvidia/Qwen3.6-35B-A3B-NVFP4` checkpoint hits a real,
currently-open vLLM bug on this hardware — a `KeyError` loading MoE expert
scale tensors ([#44081](https://github.com/vllm-project/vllm/issues/44081),
[#38980](https://github.com/vllm-project/vllm/issues/38980), both open, no
fix landed). `vllm-aux` ran a community image
(`ghcr.io/aeon-7/aeon-vllm-ultimate`) with a deliberately uncensored
("abliterated") re-quantized checkpoint as a workaround — that carried a real
trust/audit tradeoff (single-maintainer, unaudited) and put a checkpoint with
no safety guardrails behind Hermes's `approval` role. Dropped in favor of the
official `Qwen/Qwen3.6-35B-A3B-FP8` checkpoint instead: sidesteps the NVFP4
bug entirely (different quantization format, different code path — uses the
`TRITON` FP8 MoE backend, not `FLASHINFER_CUTLASS`) and removes both the
trust tradeoff and the guardrail gap.

## PVCs stay right-sized — checkpoints don't accumulate

Each PVC (`mainStorageSize: 35Gi`, `auxStorageSize: 50Gi` in
`clusters/orion/vllm.yaml`) is sized for **one** checkpoint plus headroom, not
for holding old ones alongside new — the official FP8 checkpoint alone is
~38GB, hence `aux`'s larger size vs `main`'s 27B model.

Fix for accumulation is the `clean-stale-models` initContainer on both
Deployments — deletes any `models--*` cache directory not matching the model
about to be served, every pod start. **Its `KEEP` value must be kept in sync
by hand with the `--model` arg in the same file** — no single source of truth
links them, so a checkpoint change needs both updated together, or the
initContainer deletes the checkpoint that's about to be used.

## Startup is sequenced — main first, then aux

`vllm-aux`'s `wait-for-main` initContainer blocks until `vllm-main` reports
healthy before `vllm-aux` starts loading. Time-slicing gives zero memory
isolation between the two, so simultaneous cold loads can starve each other
mid-init — sequencing keeps their memory peaks from overlapping. One-
directional and kept that way: if `vllm-main` is ever down, `vllm-aux` waits
rather than competing with it for memory.

## Known risks — read before deploying

- **`vllm-main`'s image is still unpinned.** `vllm/vllm-openai:cu130-nightly`
  is a moving tag — whatever's cached on the node from first pull is what
  runs, regardless of what the tag points to upstream now. Confirmed working
  for both checkpoints; unresolved as a general risk. Stock vLLM releases lack
  sm_121 (Blackwell) kernels for aarch64
  ([#36821](https://github.com/vllm-project/vllm/issues/36821), open) — this
  hardware needs the CUDA 13 nightly track.
- **Tool-call parser is `qwen3_coder`, not `hermes`.** Wrong parser → tool
  calls arrive as literal text JSON and Hermes fails silently.
- **`--gpu-memory-utilization` is computed against currently-free memory at
  the instant each engine initializes, not a fixed reservation.** Both set to
  0.40, comfortably above real measured weights (main 28.51GB, aux ~35GB) —
  `wait-for-main` keeps the two cold starts from overlapping, so neither
  claims its share while the other is mid-init. Still probabilistic, not a
  guarantee — a static target doesn't prevent a transient spike from a
  concurrent retry, only makes one far less likely.
- **Container memory limits matter independently of the fraction above.**
  Both measured via cgroup `memory.peak` under real concurrent load (main
  ~38GB, aux ~33GB) with the resources block sized ~20GB above that.
- **The node has rebooted spontaneously at least once, unprompted, with no
  root cause found.** Recovered cleanly on its own the second time (the
  first, earlier instance needed a manual power cycle). Watch for a pattern
  (thermal/PSU/watchdog) if it recurs — nothing in this repo triggers it
  intentionally.
- **Node taint toleration is confirmed correct.** Live-verified:
  `nvidia.com/gpu=true:NoSchedule`, and `operator: Exists` matches regardless
  of value. Still applied by hand via `kubectl taint`, not tracked in git —
  could drift.
- **Cold start is slow.** Weight download (first pull only) + JIT compile on
  every start, stacked with Kubernetes' `progressDeadlineSeconds` and the
  Flux Kustomization's own `timeout` (both set to a matching ~30-35 min
  budget — see `clusters/orion/vllm.yaml`).
- **DFlash speculative decoding isn't configured for `vllm-aux`.** Needs its
  own unmerged vLLM PR
  ([#40898](https://github.com/vllm-project/vllm/pull/40898)). Deferred,
  separate future project.

## Verify

```
kubectl describe node orion-ai-01 | grep -A5 Allocatable   # nvidia.com/gpu: 4
kubectl logs -n vllm deploy/vllm-main   # confirm reported KV cache size matches expectations
kubectl logs -n vllm deploy/vllm-aux
```
