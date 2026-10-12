# paperclip

Agent orchestrator at `paperclip.${domain}` (company W.D.O.). Postgres via CNPG
(`paperclip-db`), state on `paperclip-data`, runtime config in `config.json`
(secret-free; the DB URL comes from `DATABASE_URL`).

- **First login:** read the invite URL from `kubectl -n paperclip logs job/paperclip-bootstrap-ceo`.
- **Claude agents:** run `claude setup-token`, then create Secret `paperclip-claude`
  (key `CLAUDE_CODE_OAUTH_TOKEN`, sops) here. Optional until then.
- `forgejo-tokens.sops.yaml`: bot tokens from `task forgejo:tokens`.
