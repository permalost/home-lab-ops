# home-automation

MQTT stack: Mosquitto (broker) + Zigbee2MQTT (Zigbee bridge). Wired into
orion via `kubernetes/clusters/orion/home-automation.yaml`, namespace
`home-automation`.

## Components

| Subdirectory | Purpose |
|-------------|---------|
| `mosquitto/` | MQTT message broker. Standalone manifests, no HTTP surface — `webapp/base` doesn't buy anything here, same reasoning as `external-endpoints`. |
| `zigbee2mqtt/` | Zigbee coordinator bridge → MQTT. Built on `../../webapp/base` + `httproute`/`pvc` components, frontend at `z2m.${domain}`. |

`zigbee2mqtt/patches/`: `svc-remap-port-80.yaml` (the `httproute` component hardcodes
`backendRefs.port: 80`, so the Service gets remapped to match — same convention
`pihole` uses), `httproute-add-homepage-annotations.yaml`, and
`deploy-add-config-init.yaml` (the ConfigMap→PVC bootstrap initContainer, appends
onto the volumes the `pvc` component already added).

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
  mutating the ConfigMap.
- `permit_join: true` in zigbee2mqtt's config leaves the network open to new
  device joins indefinitely — flip to `false` in `configMap.yaml` once
  pairing is done, and re-encrypt with `sops --encrypt --in-place`.

## Troubleshooting

- **MQTT broker unreachable:** check the `mosquitto` Service and that
  `configMap.yaml` credentials (`z2m_mqtt_user` / `hass_mqtt_user`) match
  what clients use.
- **Zigbee2MQTT can't reach the coordinator:** confirm the SLZB-06 is up at
  `10.50.0.150` and its ser2net port hasn't moved from `6638`.
- **Config not applying:** the initContainer only copies config on first
  boot (`if [ ! -f configuration.yaml ]`) — delete the PVC's contents or
  exec in to force a re-copy after editing `configMap.yaml`.
