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
- `HOME_ASSISTANT_URL` (`https://ha.orion.norseamerican.com`) / `HOME_ASSISTANT_TOKEN`
  (long-lived access token, SOPS-encrypted in `secret.yaml`) are set on the
  container via `patches/deploy-add-env.yaml`, staged for the HA integration —
  not yet referenced by `config.yaml`. Home Assistant's built-in MCP server
  endpoint is `/api/mcp` (bearer auth); wiring that into `mcp_servers` is the
  next step.

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

## Ingress / Endpoints

Exposed via the `httproute` component at `hermes-hearth.${domain}`.
gethomepage.dev annotations surface it under "AI".

## Troubleshooting

See `hermes-sage/README.md` — identical failure modes (both talk to the
same `vllm-main`/`vllm-aux` backends).
