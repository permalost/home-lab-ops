---
name: maintenance
description: "Investigate a Kubernetes alert using the k8s MCP server, and open a PR for a safe fix. No exec/delete/write cluster tools exist — the only write path is a git PR, and it can never merge itself."
version: 0.2.0
author: community
license: MIT
platforms: [linux, macos, windows]
prerequisites:
  env_vars: [GITHUB_TOKEN]
  commands: [git, curl]
metadata:
  hermes:
    tags: [Kubernetes, Alerting, Troubleshooting, Diagnosis, GitOps]
    homepage: https://github.com/containers/kubernetes-mcp-server
    related_skills: []
---

# Maintenance

Investigates a firing cluster alert using the `k8s` MCP server
(read-only — see `kubernetes/apps/hermes-k8s-mcp`). There is no tool here
for delete, exec, create, update, or scale — not because you're told not
to use them, but because they don't exist in this tool set. The only way
this skill changes anything is by opening a pull request. `main` requires
review and passing CI for every credential, no exceptions — see "Opening
a fix" below.

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

If the fix is a specific, small manifest change you're confident about
(a resource limit, an env var, a typo'd field — the kind of thing this
repo's own history is full of), open a PR for it instead of only
describing it. If it's not that clean-cut — needs a design decision,
touches more than a couple of files, or you're not confident — describe
it and stop there. When in doubt, don't open the PR.

## Opening a fix

1. **Clone once, reuse after.** `/opt/data/repos/home-lab-ops` persists
   across restarts (it's on the PVC). If it's not there yet:
   ```bash
   git clone https://x-access-token:$GITHUB_TOKEN@github.com/permalost/home-lab-ops.git /opt/data/repos/home-lab-ops
   ```
   Otherwise `cd` into it and `git fetch origin && git checkout main && git pull`.
2. **Branch.** `git checkout -b fix/<short-slug> origin/main` — name it
   for what it fixes, not "hermes-fix-1".
3. **Make the one change.** Edit the file(s) directly. Don't touch
   anything the diagnosis didn't call for.
4. **Commit and push.**
   ```bash
   git add -A && git commit -m "fix: <what and why, one paragraph>"
   git push -u origin fix/<short-slug>
   ```
5. **Open the PR** via the REST API (no `gh` CLI in this image):
   ```bash
   curl -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
     -H "Accept: application/vnd.github+json" \
     https://api.github.com/repos/permalost/home-lab-ops/pulls \
     -d '{"title":"fix: ...","head":"fix/<short-slug>","base":"main","body":"..."}'
   ```
   Put the actual diagnosis in the PR body — what alert triggered this,
   what you found, why this is the fix.
6. **Report the PR URL** (from the API response's `html_url`) in your
   answer. That's the deliverable — not "fixed," a link to review.

## Pitfalls

- Don't retry a failed tool call with a manufactured different resource
  name hoping it works — if `pods_get` 404s, the pod's likely gone
  already (self-healed, or renamed on restart); say that instead of
  guessing at a name.
- `events_list` defaults to all namespaces if none given — scope it, or
  the result is noise.
- This skill can't confirm a fix worked after suggesting it. Say what you'd
  check next, not that it's resolved.
- Never push to `main` directly, and don't try to merge your own PR — both
  are blocked server-side regardless, but don't waste a turn attempting it.
- One fix per PR. If you notice a second, unrelated problem while
  investigating, mention it in your answer; don't fold it into the same
  branch.
- If `git commit` fails asking for identity, set it once:
  `git config user.email "hermes-hearth@noreply" && git config user.name "hermes-hearth"`.
