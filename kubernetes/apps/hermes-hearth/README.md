# hermes-hearth

Hermes Agent instance reserved for Home Assistant integration. See also
`hermes-sage/` (general assistant/test instance; identical setup otherwise —
full configuration notes there). Home Assistant *credentials* are wired
in (see below) but the actual tool/`mcp_servers` config in
`config/config.yaml` isn't — this instance still just talks to the same
external LLM model as `hermes-sage`.

## Configuration

- **Namespace:** `hermes-hearth`
- Same image, config shape, PVC layout, and `API_SERVER_KEY`/dashboard secret
  pattern as `hermes-sage` — see that README for details, including the
  dashboard/terminal security note.
- Size set in `clusters/orion/hermes-hearth.yaml` `postBuild.substitute`.
- Default model is the same external LLM model as `hermes-sage`.
  `providers.vllm-aux` is registered as a secondary picker option pointing at
  the same endpoint (no separate aux model) and still handles every
  `auxiliary_models` role (title/compression/approval/web_extraction).

## Model

Both the main loop and every auxiliary role point at the cluster's external
LLM model — see `kubernetes/apps/external-endpoints/main/README.md` for
which model that actually is and why. This replaced the prior in-cluster
Qwen3.6-27B/35B-A3B pair (`kubernetes/apps/vllm/`, since deleted); that
history — including the measured dense-vs-MoE latency tradeoff, which no
longer applies — is preserved in git blame on this file if it's ever useful
again.

The dashboard model picker and in-chat `/model` cannot persist a change on
either instance — see `hermes-sage/README.md` "Dashboard". Changing the
default is a git change to `config.yaml`, not a runtime one.

## Home Assistant

Hermes has a built-in HA integration (see upstream
[messaging/homeassistant docs](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/homeassistant)):
a gateway platform for realtime WebSocket events, plus four LLM-callable
tools (`ha_list_entities`, `ha_get_state`, `ha_list_services`,
`ha_call_service`) over HA's REST API.

- `HASS_URL` (`https://ha.orion.norseamerican.com`, matches
  `home-automation/homeassistant`'s `ha.${domain}` route) and `HASS_TOKEN`
  (long-lived access token, SOPS-encrypted in `secret.yaml`) are set via
  `patches/deploy-add-env.yaml` — these are the exact env var names Hermes
  expects (normally `~/.hermes/.env`; container env works the same way).
- The `ha_*` tools auto-activate on `HASS_TOKEN` alone — no further config
  needed.
- Realtime event forwarding (chat pings on state changes) is a separate,
  opt-in mechanism — needs a `platforms.homeassistant.extra` block
  (`watch_domains`/`watch_entities`/`cooldown_seconds`) in `config.yaml`,
  events are dropped by default otherwise. Not set up here yet.
- HA blocks `shell_command`/`command_line`/`python_script`/`pyscript`/
  `hassio`/`rest_command` service calls from `ha_call_service` itself
  (upstream safety restriction, not something this deployment adds).

## Skills

First skill managed in git for either Hermes instance — skills otherwise
live only on the PVC, seeded from the image. Delivered via
`skills.external_dirs` (`config.yaml`), not `skill_manage`: a second
`configMapGenerator` (`hermes-skills`) mounted as a **directory** (not
`subPath` — that doesn't pick up live ConfigMap updates) at
`/opt/skills-external`, with `items:` synthesizing the
`<category>/<name>/SKILL.md` nesting the loader expects from a flat
ConfigMap key. `external_dirs` entries are read-only and exempt from the
Curator, so nothing rewrites them.

- `skills/homebox/SKILL.md` — Homebox inventory REST API (curl + bearer
  token), same shape as the bundled `productivity/airtable` skill. Needs
  `HOMEBOX_URL`/`HOMEBOX_API_KEY` (`patches/deploy-add-env.yaml`,
  `secret.yaml`) — placeholder key pending the manual Homebox UI step, see
  `apps/homebox/README.md`.
- Also the query/write half of the Homebox → HA → ESL tag sync (see
  `apps/home-automation/homeassistant/`'s `esl_sync_labels` automation) —
  the skill can look up a location's UUID and edit it; the automation is
  what actually pushes to the physical tags.
- The skill loader is cached per session — a new skill (or an edit to one)
  needs a fresh session to show up, not just a pod restart.

## Output cap

`model.max_tokens` must be set. Unset, Hermes sends `max_tokens` equal to the
server's full `--max-model-len` (65536 on the old Qwen backend, 1048576 on
today's DeepSeek one — the bug scales with whatever the server reports), so
`input + max_tokens` always exceeds the window and vLLM 400s **every** call.
Hermes then misclassifies that 400 as input overflow —
`is_output_cap_error()` requires the literal string `max_tokens`, and vLLM's
wording says "output tokens" — and routes it into compression, which cannot
help because the input already fits.

Measured 20:50-22:28 on 2026-08-21 before the fix: 46 spurious 400s, 18
compression runs totalling 20.8 min against 3.5 min of actual inference, none
legitimately triggered (peak context 32,588 vs `threshold_tokens` 48000). Two
runs hit the 120s ceiling and gave up; one cut `messages=16->8` mid-task.

## Compression

`config.yaml`'s `compression:` block deviates from upstream defaults —
default `protect_last_n(20)+protect_first_n(3)` protects more messages than
these sessions typically contain (8-16), so the compressible middle window
was empty and compression still ran a 57-145s summarizer call for nothing.
Measured before the fix: 63 attempts, 6,131s total, 34 ended
`failure_class: no_progress`. See `agent.log` telemetry fields
`middle_window_tokens`, `total_duration_ms`, `failure_class` if tuning
further — `grep -i compress /opt/data/logs/agent.log` on the pod.

Much of what that tuning was compensating for was the output-cap 400 above
firing compression on every call. Re-measure before tuning it further.

## Alert webhook

Alertmanager POSTs to `/webhooks/cluster-alert` (port 8644,
`platforms.webhook` in `config.yaml`) on any firing `warning`/`critical`
alert, firing the `maintenance` skill — see
`infrastructure/vkms/README.md` "Alerting" for the receiver side.

The route has no `secret` key of its own — it falls back to the
platform-wide secret. Confirmed live: a config-file var reference in this
gateway config path is never expanded, so writing the secret that way just
compares every request against the literal, un-expanded text. The
platform-wide secret only gets populated correctly via the env-var enable
path (`WEBHOOK_ENABLED`+`WEBHOOK_SECRET`, both in
`patches/deploy-add-env.yaml`) — `platforms.webhook.enabled: true` in
`config.yaml` alone isn't enough to wire up the secret, only the listener.

## Ingress / Endpoints

Exposed via the `httproute` component at `hermes-hearth.${domain}`.
gethomepage.dev annotations surface it under "AI".

## Troubleshooting

See `hermes-sage/README.md` — identical failure modes (both talk to the
same external LLM model).

### Alertmanager "connection refused" to the webhook port

`AlertmanagerFailedToSendAlerts` / `AlertmanagerClusterFailedToSendAlerts`
firing with `connection refused` on `10.141.57.198:8644` (2026-09-17): the
git state was correct (config.yaml, Service, deployment all agreed on 8644)
— the gateway process inside the pod predated the config change and was
still listening on the old port, so nothing answered on 8644. Alertmanager
only sends when an alert actually fires, so the dead path stays invisible
until a real alert surfaces it via the FailedToSend meta-alerts.

Diagnosis from inside the pod (`kubectl exec -n hermes-hearth deploy/... --`):

    # What the config says the webhook port is:
    grep -B2 -A3 'port: 8644' /opt/data/config.yaml

    # What is actually listening (no ss/lsof in the image — parse
    # /proc/net/tcp directly; 0A = LISTEN, port is hex):
    python3 -c "print(sorted({int(l.split()[1].split(':')[1],16) \\
        for f in ('/proc/net/tcp','/proc/net/tcp6') \\
        for l in open(f).read().splitlines()[1:] \\
        if l.split()[3]=='0A'}))"

If the configured port is missing from the listener set, the process is
stale relative to config.yaml. Restart the gateway service so s6 respawns
it with a fresh process that re-reads config (dashboard sessions run under
a separate service and are unaffected):

    s6-svc -t /run/service/gateway-default

Verify with the listener one-liner above — the configured port must appear.
Alertmanager's retries then succeed on their own and the FailedToSend
alerts resolve. (Verified live 2026-09-17: pre-restart listeners were
8642+9119, post-restart 8642+8644+9119.)
