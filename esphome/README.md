# esphome

ESPHome device configs — not deployed by Flux, flashed directly to ESP32
hardware and adopted into Home Assistant. Lives in git for the same reason the
Talos node configs do: config-as-source, hardware itself is stateless.

## Bluetooth proxies (ble-proxy-01, ble-proxy-02)

Bluetooth proxy (`active: true`) so Home Assistant — running as a container on
Talos, which has no Bluetooth subsystem at all (`CONFIG_BT` unset in the
kernel) — can reach BLE-only devices. First consumer: the Solum Newton ESL
tags flashed by the `flash-solum-newton` skill, driven via HA's `opendisplay`
integration.

`active: true` is required, not optional — passive scanning can't sustain the
connection an image upload needs. This is also why Shelly BLE proxies don't
work for this use case.

Board is ESP32-C6 (`esp32-c6-devkitc-1` + `esp-idf` framework — not
`esp32dev`/arduino; see `ble-proxy-01.yaml`'s comment for why). Each device
needs its own `api_encryption_key`/`ota_password` in `secrets.yaml`, suffixed
`_NN` matching the file (`secrets.yaml.example` documents the pattern);
`wifi_ssid`/`wifi_password` are shared.

Placement is physical: the proxy needs to be in BLE range of the tagged boxes,
not the rack. Expect to add more `ble-proxy-NN.yaml` files as coverage areas
grow, rather than relying on one radio for the whole house.

## First run

1. Copy `secrets.yaml.example` → `secrets.yaml` (gitignored — never commit
   real Wi-Fi/API creds here; this directory has no SOPS rule).
2. `esphome run ble-proxy-NN.yaml --device /dev/cu.usbmodemXXXX` (USB) or
   `esphome upload` (OTA once initial flash is done).
3. HA: Settings → Devices & Services → **Add Integration → ESPHome** →
   host/IP + port `6053` → paste that device's `api_encryption_key`. Don't
   wait for the "discovered" section — the HA pod isn't on `hostNetwork`, so
   it never receives the proxy's mDNS broadcast; adoption has to be manual by
   IP every time.
4. Settings → Devices & Services → OpenDisplay — discovery only works once a
   proxy is adopted and a tag is powered in range.
