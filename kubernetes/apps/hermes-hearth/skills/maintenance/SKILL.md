---
name: maintenance
description: "Investigate a Kubernetes alert using the k8s MCP server. Diagnosis only — no exec, delete, or write tools exist to reach for."
version: 0.1.0
author: community
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Kubernetes, Alerting, Troubleshooting, Diagnosis]
    homepage: https://github.com/containers/kubernetes-mcp-server
    related_skills: []
---

# Maintenance

Investigates a firing cluster alert using the `k8s` MCP server
(read-only — see `kubernetes/apps/hermes-k8s-mcp`). This skill only
diagnoses. There is no tool here for delete, exec, create, update, or
scale — not because you're told not to use them, but because they don't
exist in this tool set. If a fix looks safe, describe it; don't attempt it.

## When to Use

- Triggered by the `cluster-alert` webhook route on a firing Alertmanager
  alert (fields: `alertname`, `namespace`, `severity`, `description`).
- Asked directly to check on a namespace, pod, or recent cluster event.

## Investigation

1. **Locate the resource.** `namespaces_list` if the namespace is unclear,
   otherwise `pods_list_in_namespace` for the alert's namespace.
2. **Inspect it.** `pods_get` (or `resources_get` for non-Pod kinds) for
   current state — status, restart count, conditions.
3. **Check recent history.** `events_list`, filtered to the namespace —
   scheduling failures, image pull errors, OOM kills, probe failures show
   up here before they show up in logs.
4. **Read logs.** `pods_log`. For a crash loop, set `previous: true` to get
   the last terminated container's output — the current container is often
   still initializing or has nothing useful yet. `tail` defaults to 100;
   raise it if the failure looks like it happened earlier in the log.
5. **Check node health** if the symptom looks resource-related (pod stuck
   Pending, throttling): `nodes_top`, `nodes_stats_summary`.

Cross-reference VictoriaLogs (via Grafana's datasource) for log history
beyond what `pods_log` retains, if the current/previous container logs
aren't enough. No brain-wiki cross-reference yet — that store doesn't
exist in this cluster.

## Output

A short diagnosis, not a transcript of every tool call:
- What's actually wrong (not just "the alert fired" — the underlying cause)
- Evidence for it (one or two specific findings, not everything you saw)
- A suggested fix, in enough detail that a human could act on it directly

If nothing conclusive turns up, say so plainly rather than guessing —
"crash-looping, no clear cause in events or last-container logs" is a
useful answer.

## Pitfalls

- Don't retry a failed tool call with a manufactured different resource
  name hoping it works — if `pods_get` 404s, the pod's likely gone
  already (self-healed, or renamed on restart); say that instead of
  guessing at a name.
- `events_list` defaults to all namespaces if none given — scope it, or
  the result is noise.
- This skill can't confirm a fix worked after suggesting it. Say what you'd
  check next, not that it's resolved.
