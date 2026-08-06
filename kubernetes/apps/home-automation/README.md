# home-automation

MQTT stack: Mosquitto as the broker, Zigbee2MQTT for Zigbee device
integration. Not currently wired into any cluster — kept from the
decommissioned na cluster pending migration to orion. (Home Assistant was
also part of this stack; its manifests were removed as orphaned — never
wired into a cluster.)

## Components

| Subdirectory | Purpose |
|-------------|---------|
| `mosquitto/` | MQTT message broker |
| `zigbee2mqtt/` | Zigbee coordinator bridge → MQTT |

## Configuration

Each component has its own `kustomization.yaml`, `deploy.yaml`, and `configMap.yaml`. Zigbee2MQTT publishes to Mosquitto.

## Dependencies

`mosquitto` must be ready before `zigbee2mqtt` attempts to connect to the broker.

## Troubleshooting

- **MQTT broker unreachable:** Verify the `mosquitto` Service and that credentials in `configMap.yaml` match what clients are using.
