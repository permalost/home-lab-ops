# hermes-k8s-mcp

Read-only Kubernetes visibility for hermes-hearth's `maintenance` skill, via
`containers/kubernetes-mcp-server` (native client-go, not a `kubectl`
wrapper). Wired into hermes-hearth via `mcp_servers.k8s` in
`config/config.yaml`.

Five independent read-only layers, not one:
- RBAC bound to Kubernetes' own built-in `view` ClusterRole (not hand-rolled)
- `--read-only` and `--disable-destructive` server flags
- `denied_resources` (TOML) explicitly excludes `Secret`
- `toolsets: [core]` drops the `config` toolset — its `configuration_view`
  tool returns this server's own live ServiceAccount bearer token

`ingress.enabled: false` and `fullnameOverride: k8s-mcp` are both required —
see chart defaults if changing (ingress demands a hostname by default;
without the override the Service name is chart-name-length long).
