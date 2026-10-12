# paperclip

Agent orchestrator at `paperclip.${domain}` (company W.D.O.). Postgres via CNPG
(`paperclip-db`), state on `paperclip-data`, runtime config in `config.json`
(secret-free; the DB URL comes from `DATABASE_URL`).

- **First login:** read the invite URL from `kubectl -n paperclip logs job/paperclip-bootstrap-ceo`.
  Copy the whole URL (a wrapped terminal line truncates the token).
- `forgejo-tokens.sops.yaml`: bot tokens from `task forgejo:tokens`.
- Hire approval is **off by default** in Paperclip; turn on "require board approval for new
  agents" in Company Settings, or the CEO can hire on its own.

## Claude agents

The UI's "Connect a model" step only accepts a real `claude auth login` or an Anthropic API key
(`sk-ant-api...`); it rejects the `setup-token` OAuth token (`sk-ant-oat...`).

- **Subscription token (used here):** `claude setup-token`, then `task paperclip:claude-token`
  stores it as `CLAUDE_CODE_OAUTH_TOKEN` in `secret.yaml`, which the Deployment passes to the pod.
  `claude_local` agents with no managed connection use it (Test Environment: `claude_oauth_token_configured`).
- **UI sign-in (Spiff, the first agent):** run the wizard's `claude auth login` command inside the
  pod yourself (`kubectl exec -it`), with the folder shown on screen. Don't reload the wizard
  between copying the command and pressing Connect: the folder id changes.

## Local-model agents (OpenCode on the Spark GLM)

The "New agent" form cannot create these (it forces an OpenRouter connection for OpenCode), so
agents are hired through the API with `task agent` in the **`wdo/agent-playbook`** repo on Forgejo,
which also has the full explanation and the roster. What lives here is the server side:

- `PAPERCLIP_OPENCODE_PROVIDERS` in `deployment.yaml` defines provider `spark` (OpenAI-compatible,
  `main.external-endpoints`, `limit.output: 8192` because the endpoint needs a `max_tokens` cap).
  The adapter reads it from the server env as well as the agent env; models are `spark/<model-id>`.
- Model discovery does not see it, but the image sets `OPENCODE_ALLOW_ALL_MODELS=true`, so a typed
  model is accepted.
- Check a config without creating anything: `POST /api/companies/{id}/adapters/opencode_local/test-environment`
  with `{"adapterConfig":{"model":"spark/GLM-5.3-Flash-EXL3"}}` (look for `opencode_hello_probe_passed`).

## Keep in mind

- Secrets are encrypted with `master.key` on `paperclip-data`; the stored Claude login is encrypted
  in the database. Back both up together (no backups are configured yet).
- A subscription sign-in refreshes itself but can expire; Paperclip then shows a reconnect card.
- The Spark server handles one request at a time; keep concurrent GLM agent runs low.
