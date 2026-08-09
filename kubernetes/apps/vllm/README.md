# vllm

OpenAI-compatible inference for the two Hermes agent deployments
(`kubernetes/apps/hermes-sage/`, `kubernetes/apps/hermes-hearth/`), served via
vLLM on `orion-ai-01` (DGX Spark).

Hand-written, not composed from `webapp/base` — GPU scheduling, per-model
resource sizing, and cold-start probes don't fit that template's defaults
(`cpu: 10m` / `memory: 500Mi`, no `runtimeClassName`).

## Components

| Deployment | Model | Role | Endpoint (in-cluster) |
|---|---|---|---|
| `vllm-main` | `Qwen/Qwen3.6-27B-FP8` | Hermes main model | `vllm-main.vllm.svc.cluster.local:8000` |
| `vllm-aux` | `nvidia/Qwen3.6-35B-A3B-NVFP4` | Hermes auxiliary model | `vllm-aux.vllm.svc.cluster.local:8000` |

Both are one `nvidia.com/gpu` request each, sharing the single physical GPU via
time-slicing (`kubernetes/infrastructure/nvidia-device-plugin/`, 4 replicas
advertised). Each has its own PVC — they serve different models, so nothing is
shared and no RWX/CephFS storage class is needed (`rook-ceph-block`, RWO, is
enough).

Both the Deployment and Service carry a `model` label (`qwen3.6-27b` /
`qwen3.6-35b-a3b`) — `kubectl get pods -n vllm -L model` shows what's running
without digging through container args.

## Why these two models

`Qwen3.6-27B` (dense) leads `Qwen3.6-35B-A3B` (MoE) by 8-11 points on
Terminal-Bench 2.0 and BenchLM's agentic category — the categories closest to
what Hermes actually does — at the cost of ~28-33 tok/s vs ~108 tok/s (NVFP4 +
MTP) for the MoE. Given that gap, `main` runs the agent loop and `aux` absorbs
Hermes's high-volume, low-difficulty auxiliary calls (title generation, context
compression, approval scoring, web summarization) where speed matters more than
the quality edge.

## Known risks — read before deploying

- **Image is unpinned.** `vllm/vllm-openai:cu130-nightly` is a moving tag, not a
  reproducible pin. Stock vLLM release images lack sm_121 (Blackwell) kernels
  for aarch64 ([vLLM #36821](https://github.com/vllm-project/vllm/issues/36821),
  open) — this hardware needs the CUDA 13 nightly track
  ([vLLM's own DGX Spark writeup](https://vllm.ai/blog/2026-06-01-vllm-dgx-spark)
  confirms this works). **Resolve a specific digest and pin it before merging**;
  validate it actually starts on `orion-ai-01` first. If it doesn't, fall back to
  Ollama for `vllm-aux` and re-scope.
- **Tool-call parser is `qwen3_coder`, not `hermes`.** Wrong parser → tool calls
  arrive as literal text JSON and Hermes fails silently.
- **`--gpu-memory-utilization` is a fraction of total unified memory**, shared
  by both deployments, the OS, and every other pod. `main` (0.40) + `aux` (0.30)
  = 0.70 total, deliberately under the ~0.80 threshold where GB10 has been
  reported to freeze
  ([forum report](https://forums.developer.nvidia.com/t/gemma-4-on-dgx-spark-gb10-system-freeze-at-80-utilization-sm-121-kernel-issues/366060)).
  Don't raise either without lowering the other to compensate.
- **Taint toleration is a guess.** The node's taint is applied by hand via
  `kubectl taint` (not tracked in git — `NodeRestriction` blocks Talos from
  setting it itself). Confirm the real key/value with
  `kubectl describe node orion-ai-01` before relying on the tolerations in
  `deployment-main.yaml` / `deployment-aux.yaml`.
- **Cold start is slow.** First run downloads weights to the PVC (tens of GB)
  plus ~25s JIT compile on every start. `startupProbe` is generous
  (up to 30 min) to avoid a restart-loop; if the model is still larger/slower
  than expected, extend `failureThreshold` further rather than fighting probes.

## Verify

```
kubectl describe node orion-ai-01 | grep -A5 Allocatable   # nvidia.com/gpu: 4
kubectl logs -n vllm deploy/vllm-main   # confirm reported KV cache size matches expectations
kubectl logs -n vllm deploy/vllm-aux
```
