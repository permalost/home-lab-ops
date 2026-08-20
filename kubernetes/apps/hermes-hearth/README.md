# hermes-hearth

Hermes Agent instance reserved for Home Assistant integration. See also
`hermes-sage/` (general assistant/test instance; identical setup otherwise —
full configuration notes there). Home Assistant *credentials* are wired
in (see below) but the actual tool/`mcp_servers` config in
`config/config.yaml` isn't — this instance still just talks to the local
vLLM models, same as `hermes-sage`.

## Configuration

- **Namespace:** `hermes-hearth`
- Same image, config shape, PVC layout, and `API_SERVER_KEY`/dashboard secret
  pattern as `hermes-sage` — see that README for details, including the
  dashboard/terminal security note.
- Size set in `clusters/orion/hermes-hearth.yaml` `postBuild.substitute`.
- Default model is `qwen3.6-35b-a3b` on `vllm-aux`; `vllm-main`/`qwen3.6-27b`
  is registered as a secondary picker option (see `providers:` in
  `config.yaml`) — kept mainly for `hermes-sage`, which still defaults to it.

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

## Compression

`config.yaml`'s `compression:` block deviates from upstream defaults —
default `protect_last_n(20)+protect_first_n(3)` protects more messages than
these sessions typically contain (8-16), so the compressible middle window
was empty and compression still ran a 57-145s summarizer call for nothing.
Measured before the fix: 63 attempts, 6,131s total, 34 ended
`failure_class: no_progress`. See `agent.log` telemetry fields
`middle_window_tokens`, `total_duration_ms`, `failure_class` if tuning
further — `grep -i compress /opt/data/logs/agent.log` on the pod.

## Ingress / Endpoints

Exposed via the `httproute` component at `hermes-hearth.${domain}`.
gethomepage.dev annotations surface it under "AI".

## Troubleshooting

See `hermes-sage/README.md` — identical failure modes (both talk to the
same `vllm-main`/`vllm-aux` backends).
