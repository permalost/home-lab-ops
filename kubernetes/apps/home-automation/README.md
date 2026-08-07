# home-automation

MQTT stack: Mosquitto (broker) + Zigbee2MQTT (Zigbee bridge). Not wired into
any cluster — kept from the decommissioned na cluster pending migration.

## Components

| Subdirectory | Purpose |
|-------------|---------|
| `mosquitto/` | MQTT message broker |
| `zigbee2mqtt/` | Zigbee coordinator bridge → MQTT |

## Config

Zigbee2MQTT publishes to Mosquitto; `mosquitto` must be ready first.

## Troubleshooting

- **MQTT broker unreachable:** check the `mosquitto` Service and that `configMap.yaml` credentials match what clients use.
