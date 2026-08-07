# home-automation

MQTT stack: Mosquitto (broker) + Zigbee2MQTT (Zigbee bridge). Wired into
orion via `kubernetes/clusters/orion/home-automation.yaml`, namespace
`home-automation`.

## Components

| Subdirectory | Purpose |
|-------------|---------|
| `mosquitto/` | MQTT message broker. Standalone manifests, no HTTP surface — `webapp/base` doesn't buy anything here, same reasoning as `external-endpoints`. |
| `zigbee2mqtt/` | Zigbee coordinator bridge → MQTT. Built on `../../webapp/base` + `httproute`/`pvc` components, frontend at `z2m.${domain}`. |

`zigbee2mqtt/patches/`: `httproute-add-homepage-annotations.yaml`,
`deploy-add-config-init.yaml` (the ConfigMap→PVC bootstrap initContainer, appends
onto the volumes the `pvc` component already added), and
`deploy-update-resources.yaml` (`webapp/base`'s default `cpu: 10m` throttles a
Node.js process badly — bumped to `500m`/`100m` request after confirming via
the live pod's `cgroup cpu.stat` that it was throttled >99% of the time).

## Config

- Zigbee2MQTT publishes to Mosquitto over `mqtt://mosquitto:1883`; both apps
  share the `home-automation` namespace so the short Service name resolves.
- Zigbee2MQTT's `serial.port` points at the SLZB-06 coordinator's ser2net
  TCP passthrough (`tcp://10.50.0.150:6638`) — same device wired in as
  `apps/external-endpoints/slzb-06` for its own admin UI at
  `zigbee.${domain}`. Don't confuse the two hostnames.
- Both apps write their SOPS-encrypted config directly into a ConfigMap
  (`configMap.yaml`); an initContainer copies it onto a PVC on first boot so
  the app can write its own state (device DB, retained MQTT data) without
  mutating the ConfigMap. This means editing `configMap.yaml` only affects
  *new* PVCs — an already-seeded one keeps its own copy (zigbee2mqtt owns it
  from there, e.g. writing back paired devices).
- zigbee2mqtt runs 2.x (`configMap.yaml` uses the 2.x schema: `homeassistant`
  is an object now, not a bare boolean; `frontend` needs `enabled: true`).
  Pairing new devices: **`permit_join` is not a config file setting in 2.x**
  — it was removed upstream in favor of the frontend UI or an MQTT command
  (`zigbee2mqtt/bridge/request/permit_join`, payload `{"value": true}`),
  since a static "always open" toggle in config defeats the point. Toggle it
  there when you need to pair, not here.
- Upgrading the image tag on an already-seeded PVC: zigbee2mqtt has its own
  automatic config migration (runs in-place on boot, backs up the pre-migration
  file) — no manual intervention needed even though the initContainer won't
  re-copy `configMap.yaml`'s newer schema onto an existing PVC.

## Troubleshooting

- **MQTT broker unreachable:** check the `mosquitto` Service and that
  `configMap.yaml` credentials (`z2m_mqtt_user` / `hass_mqtt_user`) match
  what clients use.
- **Zigbee2MQTT can't reach the coordinator:** confirm the SLZB-06 is up at
  `10.50.0.150` and its ser2net port hasn't moved from `6638`.
- **Config not applying:** the initContainer only copies config on first
  boot (`if [ ! -f configuration.yaml ]`) — delete the PVC's contents or
  exec in to force a re-copy after editing `configMap.yaml`.
