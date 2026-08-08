# grocy

Grocery/pantry inventory tracking (barcode scan-in, scan-out on consume,
min-stock shopping list). LinuxServer.io image — `grocy/grocy-docker` is
archived; LSIO is the maintained one.

## Configuration

- **Namespace:** `grocy`
- Container listens on `80`; `patches/` retarget the base's 8080 default
  (Deployment containerPort, Service targetPort) to match.
- PVC via the `pvc` component, mounted at `/config` — 2Gi on
  `rook-ceph-block` (see `postBuild.substitute` in
  `clusters/orion/grocy.yaml`). SQLite db and config.php live there.
- `PUID`/`PGID` set to `1000` (LSIO image requirement).

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(`grocy.orion.norseamerican.com`). gethomepage.dev annotations surface it
under "Inventory".

## First run

Log in as `admin`/`admin`, change the password, generate an API key
(Settings → Manage API keys) — needed if wiring up the Home Assistant
`rest:` sensors.

## Troubleshooting

- **Data loss after restart:** Verify the PVC is bound and mounted
  (`kubectl describe pod -n grocy`).
