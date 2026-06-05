# ai

Local AI inference stack: Ollama for model serving, LiteLLM as an OpenAI-compatible proxy, and Open WebUI as the chat interface.

## Components

| Subdirectory | Purpose |
|-------------|---------|
| `ollama/` | Pulls and serves LLM models locally |
| `litellm/` | OpenAI-compatible API proxy routing to Ollama |
| `openwebui/` | Web-based chat UI connected to LiteLLM |

## Configuration

All three components have their own `kustomization.yaml`, `deploy.yaml`, `ingress.yaml`, and `service.yaml`. LiteLLM API credentials are in `litellm/secret.yaml` (SOPS-encrypted).

## Dependencies

Requires sufficient node resources (GPU or CPU with enough RAM) for model serving. Ollama must be running before Open WebUI can reach models.

## Ingress / Endpoints

| Component | Host |
|-----------|------|
| LiteLLM | `litellm.${domain}` |
| Ollama | `ollama.${domain}` |
| Open WebUI | `open-webui.${domain}` |

## Troubleshooting

- **Models not loading in Open WebUI:** Verify Ollama has pulled the model (`kubectl exec -n ai deploy/ollama -- ollama list`).
- **LiteLLM auth errors:** Check `litellm/secret.yaml` is correctly decrypted and the API key matches.
