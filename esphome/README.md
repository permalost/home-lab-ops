# esphome

ESPHome device configs — not deployed by Flux, flashed directly to ESP32
hardware and adopted into Home Assistant. Lives in git for the same reason the
Talos node configs do: config-as-source, hardware itself is stateless.

## ble-proxy-01

Bluetooth proxy (`active: true`) so Home Assistant — running as a container on
Talos, which has no Bluetooth subsystem at all (`CONFIG_BT` unset in the
kernel) — can reach BLE-only devices. First consumer: the Solum Newton ESL
tags flashed by the `flash-solum-newton` skill, driven via HA's `opendisplay`
integration.

`active: true` is required, not optional — passive scanning can't sustain the
connection an image upload needs. This is also why Shelly BLE proxies don't
work for this use case.

Placement is physical: the proxy needs to be in BLE range of the tagged boxes,
not the rack. Expect to add more `ble-proxy-NN.yaml` files as coverage areas
grow, rather than relying on one radio for the whole house.

## First run

1. Copy `secrets.yaml.example` → `secrets.yaml` (gitignored — never commit
   real Wi-Fi/API creds here; this directory has no SOPS rule).
2. `esphome run ble-proxy-01.yaml` (USB) or `esphome upload` (OTA once initial
   flash is done).
3. HA: Settings → Devices & Services → discovered ESPHome device → adopt.
4. Settings → Devices & Services → OpenDisplay — discovery only works once a
   proxy is powered and in range of a tag.
