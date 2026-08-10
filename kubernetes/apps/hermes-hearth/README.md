# hermes-hearth

Hermes Agent instance reserved for Home Assistant integration. See also
`hermes-sage/` (general assistant/test instance; identical setup otherwise —
full configuration notes there). Home Assistant connection/tool wiring
itself isn't set up yet; this instance is currently just Hermes pointed at
the local vLLM models, same as `hermes-sage`.

## Configuration

- **Namespace:** `hermes-hearth`
- Same image, config shape, PVC layout, and `API_SERVER_KEY`/dashboard secret
  pattern as `hermes-sage` — see that README for details, including the
  dashboard/terminal security note.
- Size set in `clusters/orion/hermes-hearth.yaml` `postBuild.substitute`.

## Ingress / Endpoints

Exposed via the `httproute` component at `hermes-hearth.${domain}`.
gethomepage.dev annotations surface it under "AI".

## Troubleshooting

See `hermes-sage/README.md` — identical failure modes (both talk to the
same `vllm-main`/`vllm-aux` backends).
