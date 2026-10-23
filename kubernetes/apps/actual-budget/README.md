# actual-budget

[Actual Budget](https://actualbudget.org) — envelope-style personal
budgeting with local-first sync. `actual-server` serves both the API and the
web client from one container, so server and client are a single Deployment.

## Configuration

- **Namespace:** `actual-budget`
- Container listens on `5006`; `patches/` retarget the base's 8080 default
  (Deployment containerPort, Service targetPort) to match.
- PVC via the `pvc` component, mounted at `/data` — 2Gi on `rook-ceph-block`
  (see `postBuild.substitute` in `clusters/orion/actual-budget.yaml`). The
  budget database and server files live there.
- The image's `actual` user is uid/gid 1001; `deploy-security-context.yaml`
  sets `runAsUser`/`fsGroup` to match so the PVC is writable non-root.

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(subdomain `budget`). gethomepage.dev annotations surface it
under "Finances".

## First run

No secrets are provisioned. On first visit, set the server password in the
UI — it is stored in `/data` on the PVC. Bank sync (SimpleFIN) and OpenID,
if ever wanted, would be added here as SOPS secrets later.

## Troubleshooting

- **Data loss after restart:** Verify the PVC is bound and mounted
  (`kubectl describe pod -n actual-budget`).
- **Permission denied on /data:** Confirm `fsGroup: 1001` survived on the
  rendered pod spec (`kubectl get deploy -n actual-budget -o yaml`).
