# hermes-b

Second Hermes Agent instance — identical to `hermes-a/`, separate namespace,
PVC, and `API_SERVER_KEY`. Both point at the same `vllm-main`/`vllm-aux`
backends; vLLM's continuous batching handles the concurrent load. See
`hermes-a/README.md` for full configuration notes.
