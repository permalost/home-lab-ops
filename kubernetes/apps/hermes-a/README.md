# hermes-a

One of two Hermes Agent instances (see also `hermes-b/` — identical, separate
namespace/PVC/keys) pointed at the local vLLM stack in `kubernetes/apps/vllm/`.
No cloud API keys — `model.provider: custom` in `config/config.yaml` routes to
`vllm-main`/`vllm-aux` over the cluster network.

## Configuration

- **Namespace:** `hermes-a`
- Image `nousresearch/hermes-agent:latest`, runs `gateway run`.
- Container listens on `8642` (OpenAI-compatible API + health); `patches/`
  retarget the base's 8080 default (Deployment containerPort, Service
  targetPort) to match.
- PVC via the `pvc` component, mounted at `/opt/data` (sessions, memories,
  skills, logs) — size set in `clusters/orion/hermes-a.yaml`
  `postBuild.substitute`.
- `config/config.yaml` ships through git as a ConfigMap, projected via
  `subPath` onto `/opt/data/config.yaml` — not part of the PVC, so config
  changes are a normal PR, not a manual edit on the volume.
- `secret.yaml` (SOPS-encrypted) holds `API_SERVER_KEY`, required because
  `API_SERVER_ENABLED=true`.
- `PUID`/`PGID` set to `1000`.

## Ingress / Endpoints

Exposed via the `httproute` component — optional, only useful for reaching the
dashboard/API from outside the cluster. Nothing in this stack requires it:
Hermes talks to vLLM over in-cluster DNS, and there's no scheduled reason for
external traffic to reach Hermes itself yet.

## Troubleshooting

- **Tool calls failing / malformed:** check `vllm-main`/`vllm-aux` logs first —
  wrong `--tool-call-parser` there is the most likely cause, not this app.
- **Config not taking effect:** confirm the ConfigMap regenerated (kustomize
  content-hashes it) and the pod actually restarted — `kubectl rollout restart
  deploy/hermes-a-deploy -n hermes-a`.
