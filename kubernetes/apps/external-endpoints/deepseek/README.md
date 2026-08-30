# deepseek

Selector-less Service + EndpointSlice for the cluster's external LLM
backend — a dual-Spark pair (`spark-5a0c` + a second Spark), standalone
outside Talos/Flux, reached at `deepseek.external-endpoints.svc.cluster.local:8888`.
This is the **single place** that names which model is actually being
served — `hermes-sage`/`hermes-hearth` and anything else in this cluster
should say "the external LLM model" and link here rather than naming it
themselves, so a future model swap is a one-file change.

**Currently serving:** DeepSeek-V4-Flash-0731 (`deepseek-v4-flash-dspark`),
NVFP4, TP=2 across the Spark pair, DSpark speculative decoding, 1M-token
context ceiling. Tool-call parser `deepseek_v4`. Retired the prior in-cluster
Qwen3.6-27B/35B-A3B pair (`kubernetes/apps/vllm/`, deleted) — see the
dual-Spark migration plan (`please-run-through-preparations-wobbly-hellman.md`)
for the memory/architecture rationale.

To point the cluster at a different model or a different backend entirely:
update `endpointslice.yaml`'s address/port here, update this file's "Currently
serving" line, and update `model.default` / `providers.vllm-aux.models` /
`auxiliary_models.*.model` in both Hermes `config.yaml`s to the new
`--served-model-name`. Nothing else in either app should need to change.
