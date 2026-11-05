# hermes-dev

A Hermes agent that Paperclip drives as a developer, for the Hobbes-versus-Hermes A/B on the
same local GLM. Same image and model setup as `hermes-sage`; differences:

- **API over HTTPS:** `https://hermes-dev.${domain}` routes to the API (8642), not the
  dashboard. Paperclip's `hermes_gateway` adapter must use `https://`: with plain `http://` its
  environment test warns and agent verification fails (`harness_test_failed`).
- **No dashboard, no TokenTelemetry, no Telegram, no MCP.** Read run history with
  `kubectl -n hermes-dev exec deploy/hermes-dev-deploy -- ls /opt/data/sessions`.
- **Tools:** terminal, file, skills, todo, web (`platform_toolsets.api_server`); no memory tool.
- **`approvals.mode: "off"`:** the gateway cannot answer approval prompts. The pod has no
  kubeconfig; its only credential is a fork-scoped GitHub token.
- **Skill `dev`:** the developer playbook, generated from `wdo/agent-playbook` by
  `task paperclip:hermes-dev-skill` so Hobbes and this agent follow the same text.

## Secrets (`secret.yaml`, sops)

`API_SERVER_KEY` is set. Add the other two with `sops set` (both optional, so the pod starts
without them):

- `DEV_GITHUB_TOKEN`: fine-grained token on the `shaved-monkey` fork (Contents, Pull requests).
  Not named `GITHUB_TOKEN`: Hermes strips that from terminal commands.
- `PAPERCLIP_API_KEY`: claimed once when the agent joins Paperclip (below).

## Join Paperclip

After Flux has applied this, from the Paperclip pod's `scripts/smoke/hermes-gateway-join.sh`
(copy it with `kubectl exec ... cat`), with `HERMES_GATEWAY_API_BASE_URL=https://hermes-dev.<domain>`,
`HERMES_GATEWAY_API_KEY` set to `API_SERVER_KEY`, `PAPERCLIP_API_URL_FOR_HERMES=https://paperclip.<domain>`
and `HERMES_JOIN_OUTPUT_FILE` pointing at a private path. The output file holds the claimed key.

Trial plan and decision rule: `~/.claude/plans/we-want-to-analyze-replicated-moore.md` (local).
