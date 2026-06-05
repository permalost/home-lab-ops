# home-automation

Home automation stack: Home Assistant for device control and automation, Mosquitto as the MQTT broker, and Zigbee2MQTT for Zigbee device integration.

## Components

| Subdirectory | Purpose |
|-------------|---------|
| `home-assistant/` | Home automation platform and UI |
| `mosquitto/` | MQTT message broker |
| `zigbee2mqtt/` | Zigbee coordinator bridge → MQTT |

## Configuration

Each component has its own `kustomization.yaml`, `deploy.yaml`, and `configMap.yaml`. Components communicate internally: Zigbee2MQTT publishes to Mosquitto; Home Assistant subscribes via MQTT integration.

## Dependencies

`mosquitto` must be ready before `zigbee2mqtt` and Home Assistant attempt to connect to the broker.

## Ingress / Endpoints

| Component | Host |
|-----------|------|
| Home Assistant | `hass.${domain}` |
| HA Code Server | `hass-code.${domain}` |

## Troubleshooting

- **Zigbee devices not appearing in Home Assistant:** Check Zigbee2MQTT logs for coordinator connectivity and MQTT broker connection.
- **MQTT broker unreachable:** Verify the `mosquitto` Service and that credentials in `configMap.yaml` match what clients are using.
