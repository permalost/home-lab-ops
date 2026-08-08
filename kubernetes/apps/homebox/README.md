# homebox

Home inventory management application. Built on the shared `webapp` base with
the `httproute` and `pvc` components — canonical example for `apps/webapp/`.

## Configuration

- **Namespace:** `homebox`
- Container listens on `7745`; `patches/` retarget the base's 8080 default
  (Deployment containerPort, Service targetPort) to match.
- PVC via the `pvc` component, mounted at `/data` — 2Gi on `rook-ceph-block`
  (see `postBuild.substitute` in `clusters/orion/homebox.yaml`).

## Ingress / Endpoints

Exposed via the `httproute` component at `${subdomain}.${domain}`
(`inventory.orion.norseamerican.com`). gethomepage.dev annotations on the
route surface it on the dashboard under "Inventory".

## Troubleshooting

- **Data loss after restart:** Verify the PVC is bound and the pod is mounting it correctly (`kubectl describe pod -n homebox`).
