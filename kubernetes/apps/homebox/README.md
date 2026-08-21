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

## Label maker / ESL tags

`HBOX_LABEL_MAKER_WIDTH`/`HEIGHT` are set to 360×184 — the Solum Newton ESL
tags' effective canvas (see `~/.claude/skills/flash-solum-newton`), not
Homebox's 526×200 default. This is instance-wide, so **paper label printing
also renders at 360×184** now. `GET /api/v1/labelmaker/location/{id}` is
polled by Home Assistant to push each location's label to its paired tag —
see `apps/home-automation/homeassistant/configMap.yaml`.

## First run

1. Log in as `admin`/`admin`, change the password.
2. Settings → Manage API keys → generate one. Replace the
   `homeboxApiKey` placeholder in `secret.yaml`, and its two consumers:
   `GROCY`-style header in the HA `rest:`/`shell_command` config, and
   `HOMEBOX_API_KEY` in `apps/hermes-hearth/secret.yaml`.

## Troubleshooting

- **Data loss after restart:** Verify the PVC is bound and the pod is mounting it correctly (`kubectl describe pod -n homebox`).
