# forgejo-runner

Forgejo Actions runner (org `wdo`) with a pod-private dind sidecar. Registers
once with the org token in `secret.yaml` (`task forgejo:runner-token`), state on
`runner-data`. Egress is limited to DNS, Forgejo and the internet (`network-policy.yaml`).
`register` is deprecated in runner v13 but is the only token-based path.
