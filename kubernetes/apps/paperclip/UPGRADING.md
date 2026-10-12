# Upgrading Paperclip

Several things here work around gaps in the Paperclip version we run. After a version bump, re-test
each one and remove the workarounds that are no longer needed.

**Validated against:** `2026.1005.0` (2026-10-12).

Run the automated part (in the `wdo/agent-playbook` checkout, after the new pod is up):

```sh
task upgrade-check                # read-only checks, a few seconds
task upgrade-check HANDOFF=1      # also the end-to-end handoff test (one local run + maybe one short Claude run)
```

Then do the manual checks below, update the version above, and remove whatever turned out unnecessary.

| # | Workaround | Why | Re-test | If fixed |
|---|---|---|---|---|
| W1 | Reviewer timer heartbeat (30 min, `agents/<Susie>` runtimeConfig) | The review stage did not wake the reviewer at the handoff (no run is created) | `task upgrade-check HANDOFF=1` | Disable the reviewer's heartbeat (`enabled: false`); it costs about 9k tokens per idle tick |
| W2 | Agents hired through the API (`task agent`) | The New agent form forces an OpenRouter connection onto OpenCode agents and has no env editor | Manual: `/agents/new`, OpenCode, type model `spark/GLM-5.3-Flash-EXL3`; does Test pass and can you save? | Hiring in the UI becomes possible; the API route still works, so this is optional |
| W3 | `CLAUDE_CODE_OAUTH_TOKEN` from the pod env | The connect step rejects the `setup-token` OAuth token | Automated: `claude_oauth_token_configured`. Manual: does the connect step now accept it? | Could use a managed connection instead of the env token |
| W4 | "Require board approval for new agents" turned on | Off by default; the stock CEO hires on its own | Automated | Nothing to remove; confirm it is still on |
| W5 | `PAPERCLIP_OPENCODE_PROVIDERS` in `deployment.yaml` | Custom OpenCode providers cannot be set in the UI; model discovery ignores them | Automated: `opencode_hello_probe_passed` | If the UI gains custom providers, move it there |
| W6 | Master key and database not backed up | Not a Paperclip gap, an open task here | Check that backups exist | n/a |
| W7 | `task agent:sync` writes through `PUT .../instructions-bundle/file` | Paperclip keeps its own copy of agent instructions | Automated: the sync check runs clean | n/a |

Also glance at the release notes for breaking changes (the 2026.1005.0 notes listed three), and run one
real task through Developer and Reviewer afterwards (the WDO-3/WDO-4 flow) before trusting the upgrade.

If the image tag lives in both `deployment.yaml` and `bootstrap-job.yaml`, bump both.
