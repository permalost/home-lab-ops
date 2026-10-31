# paperclip

Agent orchestrator at `paperclip.${domain}` (company W.D.O.). Postgres via CNPG
(`paperclip-db`), state on `paperclip-data`, runtime config in `config.json`
(secret-free; the DB URL comes from `DATABASE_URL`).

- **First login:** read the invite URL from `kubectl -n paperclip logs job/paperclip-bootstrap-ceo`.
  Copy the whole URL (a wrapped terminal line truncates the token).
- `forgejo-tokens.sops.yaml`: bot tokens from `task forgejo:tokens`.
- `github-tokens.sops.yaml`: PAT for Hobbes's GitHub fork account (`public_repo`, no write on this repo);
  wired into the agent by `task agent:github` in `wdo/agent-playbook`.
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

## Hobbes's read-only cluster access

Hobbes (local GLM) is the only agent with Kubernetes API access (Jon's decision on
WDO-143). The credential is his alone: the `hobbes-readonly` ServiceAccount has a
read-only ClusterRole (`get`/`list`/`watch`, Secrets excluded — see
`kubernetes/infrastructure/rbac/`), and a long-lived token in Secret
`hobbes-readonly-token`. The token controller fills that Secret after the first
apply; such tokens do not expire or rotate, and none of it is committed to git.
Paperclip injects it only into Hobbes's adapter env, never into the pod spec.

Setup (Jon, after the merge):

1. Read the token and the CA (give Flux a minute to apply and the token controller
   to populate the Secret):
   ```bash
   kubectl -n paperclip get secret hobbes-readonly-token -o jsonpath='{.data.token}' | base64 -d
   kubectl -n paperclip get secret hobbes-readonly-token -o jsonpath='{.data.ca\.crt}' | base64 -d
   ```
2. Store each value as a Paperclip secret (`POST /api/companies/{companyId}/secrets`,
   names `hobbes-kubernetes-token` and `hobbes-kubernetes-ca`), then bind them to
   Hobbes's adapter env only: set `adapterConfig.env.KUBERNETES_TOKEN` and
   `adapterConfig.env.KUBERNETES_CA` to `{"type":"secret_ref","secretId":"<id>","version":"latest"}`
   and PATCH the agent. Do not put them in the Deployment. The redaction caveat from
   `wdo/agent-playbook` `scripts/paperclip-agent-github.sh` applies: read the agent,
   change only the two keys, PATCH back.
3. No setup is needed for the API address: the kubelet sets `KUBERNETES_SERVICE_HOST`
   and `KUBERNETES_SERVICE_PORT` in every pod, also with automount off. `ca.crt`
   is not: the whole `/var/run/secrets/kubernetes.io/serviceaccount/` directory is
   gone, hence the CA env var.
4. Rotate: delete the Secret (`kubectl -n paperclip delete secret hobbes-readonly-token`;
   Flux re-applies the skeleton and the controller fills a fresh token), then update
   the two Paperclip secrets.

What a Hobbes run then looks like (the read-only call succeeds, the Secret call is
refused with 403):

```bash
printf '%s' "$KUBERNETES_CA" > /tmp/hobbes-ca.crt
API="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
# Expected: exit 0, HTTP 200, and a PodList document.
curl --fail --silent --cacert /tmp/hobbes-ca.crt \
  -H "Authorization: Bearer $KUBERNETES_TOKEN" \
  "$API/api/v1/namespaces/paperclip/pods?limit=1"
# Expected: HTTP 403 with a Status document, "reason": "Forbidden"
# ("...cannot list resource \"secrets\" in API group \"\" in the namespace
# \"paperclip\""); the token is valid, the role just excludes Secrets.
# Without --fail this prints the body instead of erroring, so a 403 shows
# up as JSON, not as a failed command.
curl --silent --cacert /tmp/hobbes-ca.crt \
  -H "Authorization: Bearer $KUBERNETES_TOKEN" \
  "$API/api/v1/namespaces/paperclip/secrets?limit=1"
```

The limit, plainly: every agent in the Paperclip pod runs as uid 1000. Paperclip
injects adapter env only into that agent's runs and redacts env values over the
API, but any agent process could read another agent's env in `/proc`. This is a
policy boundary, not enforcement.

## Keep in mind

- The pod itself has no Kubernetes API access: it runs with `automountServiceAccountToken: false`
  and no RBAC binding on its ServiceAccount. The token file stays in a running pod until
  the pod restarts, so delete the pod after merging a token change. The
  `@paperclipai/plugin-kubernetes` sandbox provider is the only Paperclip feature that
  reads the token; it is not installed here. The one exception is Hobbes's own
  read-only credential, injected into his adapter env (below) — it is never mounted
  into the pod.
- Secrets are encrypted with `master.key` on `paperclip-data`; the stored Claude login is encrypted
  in the database. Back both up together (no backups are configured yet).
- A subscription sign-in refreshes itself but can expire; Paperclip then shows a reconnect card.
- The Spark GLM server takes 4 concurrent requests (`MAX_NUM_SEQS=4`), shared with Hermes. One stream runs about
  25 tok/s, four about 10 each. Keep concurrent GLM agent runs low.

Upgrading: see `UPGRADING.md` (workarounds to re-test after a version bump).
