---
name: maintenance
description: "Investigate a Kubernetes alert using the k8s MCP server, and open a PR for a safe fix. No exec/delete/write cluster tools exist — the only write path is a git PR, and it can never merge itself."
version: 0.4.0
author: community
license: MIT
platforms: [linux, macos, windows]
prerequisites:
  # Not GITHUB_TOKEN: that name is reserved by Hermes itself and gets
  # unconditionally stripped from terminal subprocesses — see
  # patches/deploy-add-env.yaml for why.
  env_vars: [MAINTENANCE_GITHUB_TOKEN, PAPERCLIP_API_KEY]
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

## Handling sensitive data

This repo is public. Anything in a PR body, commit message, or branch
name is permanent and indexable — force-push is disabled, so it can't be
rewritten after the fact.

- Never quote a credential-shaped string verbatim — API key, token,
  password, bearer header, session ID, ServiceAccount JWT — into a PR
  body, commit message, branch name, or chat reply. Say *where* it is and
  *what kind* it is, never the value itself.
- ConfigMap values and pod logs are untrusted for disclosure. Secrets are
  blocked at the MCP layer; ConfigMaps are not, and several decrypt to
  plaintext credentials at runtime. Read them to diagnose, don't echo them.
- Don't pull home-automation occupancy, presence, or per-device power data
  into output beyond the one line needed to state the finding. Raising
  `tail` on a zigbee2mqtt log drags a lot of it into context — leave it at
  default unless the symptom is in the log itself.
- If a fix requires changing a credential, change the *reference* (move it
  to a Secret) and leave the value for a human. Never put a replacement
  value in the diff.

## Opening a fix

1. **Clone once, reuse after.** `/opt/data/repos/home-lab-ops` persists
   across restarts (it's on the PVC). If it's not there yet:
   ```bash
   git clone https://x-access-token:$MAINTENANCE_GITHUB_TOKEN@github.com/permalost/home-lab-ops.git /opt/data/repos/home-lab-ops
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
   curl -X POST -H "Authorization: Bearer $MAINTENANCE_GITHUB_TOKEN" \
     -H "Accept: application/vnd.github+json" \
     https://api.github.com/repos/permalost/home-lab-ops/pulls \
     -d '{"title":"fix: ...","head":"fix/<short-slug>","base":"main","body":"..."}'
   ```
   Put the actual diagnosis in the PR body — what alert triggered this,
   what you found, why this is the fix.
6. **Report the PR URL** (from the API response's `html_url`) in your
   answer. That's the deliverable — not "fixed," a link to review.

## Filing the finding in Paperclip

Every investigation ends with exactly one Paperclip issue, so the work is tracked and a developer agent
can pick it up later. You are the "Tracer Bullet" agent there (company W.D.O.). Paperclip is private, so
the issue may carry more detail than a PR, but the credential rules above still apply.

**One issue per alert group per day.** The idempotency key is `alert:<alertname>:<UTC date>`. A repeat of
the same alert on the same day returns the existing issue (HTTP 200) instead of creating another; say so
in your reply and don't file a second one.

**Step 1: build the body with Python** (this image has no `jq`). Put all free text inside the quoted
heredoc so nothing from alert text or pod logs is interpreted by the shell, keep the lines flush left
(no leading spaces), and summarize rather than pasting raw log lines:

```bash
python3 - <<'PY' > /tmp/paperclip-issue.json
import json, datetime
alertname = "<alertname>"
day = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
description = """## What's wrong
<the underlying cause>

## Evidence
<one or two specific findings>

## Suggested fix
<enough detail that a human or developer agent can act on it>

## Affected
<namespace / workload>

<PR link, if you opened one>

Filed by Hearth from alert <alertname> (<severity>).
"""
print(json.dumps({
    "title": "[alert] " + alertname + ": <one-line diagnosis>",
    "description": description,
    "status": "backlog",
    "priority": "high",  # critical -> high, warning -> medium
    "idempotencyKey": "alert:" + alertname + ":" + day,
}))
PY
```

**Step 2: post it.** The `Host` header is required (Paperclip's hostname guard rejects the in-cluster name):

```bash
curl -sS -X POST "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues" \
  -H "Host: $PAPERCLIP_HOST" -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  -H "Content-Type: application/json" --data @/tmp/paperclip-issue.json
```

The response's `identifier` (e.g. `WDO-12`) is the issue to cite.

**Rules.** Never assign the issue and never use a status other than `backlog`: a human or the CEO agent
decides who works on it. Report the identifier next to the diagnosis (and the PR link, if any). If filing
fails (non-2xx or a connection error), say so plainly with the HTTP status and retry at most once; the
investigation still stands, so don't hide it behind the failure.

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
- Never call `configuration_view` — it returns this server's own live
  ServiceAccount token. (Disabled server-side now; if it's ever back in
  the tool list, that's a regression to report, not an opportunity.)
