# hermes-sage

General-purpose Hermes Agent instance — assistant duties and the instance
used for testing/iterating on the local model stack. See also
`hermes-hearth/` (Home Assistant integration; identical setup otherwise).
Pointed at the local vLLM stack in `kubernetes/apps/vllm/` — no cloud API
keys, `model.provider: custom` in `config/config.yaml` routes to
`vllm-main`/`vllm-aux` over the cluster network.

## Configuration

- **Namespace:** `hermes-sage`
- Image `nousresearch/hermes-agent:latest`, runs `gateway run`.
- Container listens on `8642` (OpenAI-compatible API + health); `patches/`
  retarget the base's 8080 default (Deployment containerPort, Service
  targetPort) to match.
- PVC via the `pvc` component, mounted at `/opt/data` (sessions, memories,
  skills, logs) — size set in `clusters/orion/hermes-sage.yaml`
  `postBuild.substitute`.
- `config/config.yaml` ships through git as a ConfigMap, projected via
  `subPath` onto `/opt/data/config.yaml` — not part of the PVC, so config
  changes are a normal PR, not a manual edit on the volume.
- `secret.yaml` (SOPS-encrypted) holds `API_SERVER_KEY`, required because
  `API_SERVER_ENABLED=true`.
- `PUID`/`PGID` set to `1000`.

## Dashboard

`hermes-agent` runs the dashboard as a separate s6 service on its own port
(`9119`, distinct from the API's `8642`) — gated behind `HERMES_DASHBOARD`,
which does nothing unless set (the service exits immediately and stays
"supervised, permanent failure" otherwise). Enabled here via
`deploy-add-env.yaml`. Includes the embedded xterm.js terminal, running
against `terminal.backend: local` (the framework default — commands execute
directly in this pod's own container, not a further-sandboxed nested
container; the pod boundary is the only isolation). Revisit if that's not
acceptable — `terminal.backend: docker` needs Docker-in-Docker or a sidecar
daemon, real added complexity not set up here.

A non-loopback dashboard bind (`0.0.0.0`, required to reach it through the
Service) fails closed without a registered auth provider. Wired up here with
the bundled zero-IDP basic-auth plugin — `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`/
`_PASSWORD` in `secret.yaml` (SOPS-encrypted, plaintext accepted — hashed
in-memory at load, not stored hashed at rest).

`httproute-dashboard-port.yaml` points external traffic at the dashboard port
(`9119`) instead of the bare API (`8642`) — the API remains reachable
in-cluster via the Service's `http` port if anything ever needs it, just not
externally routed.

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(`hermes-sage.orion.norseamerican.com`) — optional, only useful for reaching
the dashboard from outside the cluster. gethomepage.dev annotations surface
it under "AI". Nothing in this stack requires external access: Hermes talks
to vLLM over in-cluster DNS.

## Troubleshooting

- **Tool calls failing / malformed:** check `vllm-main`/`vllm-aux` logs first —
  wrong `--tool-call-parser` there is the most likely cause, not this app.
- **Config not taking effect:** confirm the ConfigMap regenerated (kustomize
  content-hashes it) and the pod actually restarted — `kubectl rollout restart
  deploy/hermes-sage-deploy -n hermes-sage`.
