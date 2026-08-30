# main / aux

Selector-less Service + EndpointSlice pairs for the cluster's external LLM
model(s) — `main` (the primary Hermes model) and the sibling
`aux-endpoint/` directory (Service/EndpointSlice name `aux`; auxiliary
roles: title/compression/approval/web_extraction). Directory is named
`aux-endpoint` rather than `aux` because Flux's source-controller (go-git)
rejects any git path component matching a reserved Windows device name
(`aux`, `con`, `nul`, `com1-9`, `lpt1-9`) — the k8s object name itself is
unaffected.
Named after the role, not the model, so a future model swap never touches
these directory/resource names — only `endpointslice.yaml`'s address/port
here and the model-id strings in each Hermes `config.yaml`.

This is the **single place** that names which model is actually being
served — `hermes-sage`/`hermes-hearth` and anything else in this cluster
should say "the external LLM model" and link here rather than naming it
themselves.

**Currently serving (both `main` and `aux`, same backend today):**
DeepSeek-V4-Flash-0731 (`deepseek-v4-flash-dspark`), NVFP4, TP=2 across a
dual-Spark pair (`spark-5a0c` + a second Spark), standalone outside
Talos/Flux, at `10.50.0.126:8888`. DSpark speculative decoding, 1M-token
context ceiling. Tool-call parser `deepseek_v4`. Retired the prior
in-cluster Qwen3.6-27B/35B-A3B pair (`kubernetes/apps/vllm/`, deleted) — see
the dual-Spark migration plan
(`please-run-through-preparations-wobbly-hellman.md`) for the
memory/architecture rationale.

`main` and `aux` are separate Service+EndpointSlice pairs on purpose, even
though they point at the same address today — if a distinct, smaller aux
model ever comes back, only `aux-endpoint/endpointslice.yaml` needs to change.

To point the cluster at a different model or backend: update
`endpointslice.yaml`'s address/port in `main/` and/or `aux-endpoint/`, update this
file's "Currently serving" line, and update `model.default` /
`providers.vllm-aux.models` / `auxiliary_models.*.model` in both Hermes
`config.yaml`s to the new `--served-model-name`. Nothing else in either app
should need to change.
