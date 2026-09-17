# hermes-k8s-mcp

Read-only Kubernetes visibility for hermes-hearth's `maintenance` skill (not
yet built — see `~/.claude/plans/alerts-logs-hermes-maintenance.md`), via
`manusa/kubernetes-mcp-server` (native client-go, not a `kubectl` wrapper).
Wired into hermes-hearth via `mcp_servers.k8s` in `config/config.yaml`.

Four independent read-only layers, not one:
- RBAC bound to Kubernetes' own built-in `view` ClusterRole (not hand-rolled)
- `--read-only` and `--disable-destructive` server flags
- `denied_resources` (TOML) explicitly excludes `Secret`

`ingress.enabled: false` and `fullnameOverride: k8s-mcp` are both required —
see chart defaults if changing (ingress demands a hostname by default;
without the override the Service name is chart-name-length long).
