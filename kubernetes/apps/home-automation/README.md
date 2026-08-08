# home-automation

MQTT stack + Home Assistant, namespace `home-automation` for all three apps
(so they can reach `mosquitto` by short name). Wired into orion via
`kubernetes/clusters/orion/home-automation.yaml`, which holds **two** Flux
Kustomization CRs (`---`-separated in one file, same pattern
`cert-manager.yaml`/`gateway.yaml` already use for co-located CRs):

- `home-automation` → `./kubernetes/apps/home-automation` (mosquitto + zigbee2mqtt)
- `homeassistant` → `./kubernetes/apps/home-automation/homeassistant` directly (bypasses the aggregator)

## Components

| Subdirectory | Purpose |
|-------------|---------|
| `mosquitto/` | MQTT broker. Standalone manifests, no HTTP surface — `webapp/base` doesn't buy anything here. |
| `zigbee2mqtt/` | Zigbee coordinator bridge → MQTT. Built on `../../webapp/base` + `httproute`/`pvc` components, frontend at `z2m.${domain}`. |
| `homeassistant/` | Home Assistant. Also built on `../../webapp/base` + `httproute`/`pvc` components, frontend at `ha.${domain}`. |

### Why homeassistant is a separate Flux Kustomization CR

One Flux `Kustomization` = one flat `postBuild.substitute` namespace — every
`${VAR}` in its entire rendered output gets replaced from the same map, with
no per-resource scoping. The `httproute`/`pvc` components both rely on
generic vars (`${appName}`, `${subdomain}`, `${storageClass}`/`${storageSize}`)
that need *different* values per app. `zigbee2mqtt` already claims those
inside the `home-automation` Kustomization; folding `homeassistant` into the
same one would mean both apps' `HTTPRoute`s resolving `${subdomain}` to
whichever value happened to be set last — silently wrong, not a build error.

Giving `homeassistant` its own Kustomization CR (pointing directly at
`homeassistant/`, skipping the `mosquitto`+`zigbee2mqtt` aggregator) gives it
its own substitute namespace, so both apps get full, uncompromised use of the
shared components. `${domain}`/`${gatewayName}` don't have this problem —
those come from `cluster-settings` (`substituteFrom`, not the literal
`substitute` map) and are genuinely the same value for every app in the
cluster.

If a fourth home-automation app needs `httproute`/`pvc`, give it a third Flux
Kustomization CR the same way, or hardcode its resources like `mosquitto/`
does if it doesn't need real parameterization.

### The seed-config pattern (all three apps)

Each app's `configMap.yaml` (SOPS-encrypted) holds its initial config; an
initContainer copies it onto a PVC. None of these apps should have their
whole config directory overwritten on every boot — they write real state
into it (zigbee2mqtt: paired devices, network key; Home Assistant: the
recorder DB, `.storage/`; mosquitto's is closer to stateless, but the
pattern's kept consistent).

- **zigbee2mqtt / homeassistant** use a `SEED_VERSION` marker
  (`.z2m-seed-version` / `.seed-version` on the PVC): re-copies only when the
  version baked into the initContainer's `args` doesn't match what's
  recorded on the PVC, otherwise leaves it alone. Bump the version any time
  `configMap.yaml`'s config content changes and needs to land on an
  already-seeded PVC.
- **mosquitto**'s initContainer re-copies unconditionally on every boot
  (its config is simple enough that this is safe), so ConfigMap changes
  need a pod restart to take effect — nothing kubectl-mutates that
  automatically, so `deployment.yaml`'s pod template carries a
  `home-lab-ops/config-generation` annotation to bump by hand when that's
  needed (forces a real rollout since the pod template itself changes).

## Config

- Zigbee2MQTT and Home Assistant both talk to Mosquitto over
  `mosquitto:1883` / `mosquitto.home-automation.svc.cluster.local:1883`
  (short name works since they're all in the same namespace).
- Zigbee2MQTT's `serial.port` points at the SLZB-06 coordinator's ser2net
  TCP passthrough (`tcp://10.50.0.150:6638`) — same device wired in as
  `apps/external-endpoints/slzb-06` for its own admin UI at
  `zigbee.${domain}`. Don't confuse the two hostnames. `serial.adapter:
  zstack` is required explicitly (zigbee-herdsman 10.x can't auto-detect
  over TCP) — confirmed against this coordinator's own logs (TI CC2652).
- zigbee2mqtt runs 2.x. `permit_join` is **not** a config file setting in
  2.x — toggle it via the frontend or
  `zigbee2mqtt/bridge/request/permit_join` (`{"value": true}`) when
  pairing new devices, not in git.
- Home Assistant's reverse-proxy trust (`use_x_forwarded_for` /
  `trusted_proxies: 10.241.0.0/16`, orion's pod CIDR from `talconfig.yaml`)
  is seeded via `.storage/http` (`homeassistant/configMap.yaml`'s
  `http-storage.json` key), **not** `configuration.yaml`'s `http:` block.
  HA stages YAML `http:` config as an unconfirmed "pending" trial that
  auto-reverts (and restarts) if nothing promotes it within 5 minutes of
  boot — fine if a human's watching the UI, impossible for an unattended
  GitOps deploy, and once it fails the trial it's marked "never retry" and
  won't self-heal on the next restart either. Seeding storage directly,
  pre-marked `stable`, skips the trial. Also matches where upstream is
  headed anyway: YAML `http:` config is deprecated as of this HA version,
  breaking entirely in 2027.2.0. `homeassistant.external_url` still comes
  from `configuration.yaml` as normal. Resource limits are set well above
  `webapp/base`'s defaults from the start (`1` cpu / `1Gi` mem limit) —
  zigbee2mqtt's `webapp/base` default of `cpu: 10m` throttled it badly
  (#90); no reason to rediscover that here.
- **First boot of Home Assistant needs a human**: visiting `ha.${domain}`
  walks through HA's own onboarding (create the admin account, name the
  instance) — nothing about that is config-file-representable, so it isn't
  automated here. After that, add the MQTT integration via *Settings →
  Devices & services → Add integration → MQTT*
  (`homeassistant/secret.yaml` has the broker credentials —
  `mosquitto.home-automation.svc.cluster.local:1883`). zigbee2mqtt is
  already publishing `homeassistant/...` discovery topics, so paired
  Zigbee devices should show up automatically once MQTT is connected.
- `mosquitto/configMap.yaml`'s `hass_mqtt_user` password was regenerated
  from scratch when `homeassistant/` was added — the original (na-era)
  plaintext was never recoverable, mosquitto only ever stored the hash.
  The new plaintext lives in `homeassistant/secret.yaml` (SOPS).

## Troubleshooting

- **MQTT broker unreachable:** check the `mosquitto` Service and that the
  credentials in use (`z2m_mqtt_user` / `hass_mqtt_user`) match
  `mosquitto/configMap.yaml`'s `password_file`.
- **Zigbee2MQTT can't reach the coordinator:** confirm the SLZB-06 is up at
  `10.50.0.150` and its ser2net port hasn't moved from `6638`.
- **Home Assistant rejects requests / login weirdness behind the Gateway,
  or logs "A request from a reverse proxy was received... not set-up for
  reverse proxies":** check `.storage/http`'s `stable.trusted_proxies`
  (not `configuration.yaml` — see above) still covers the pod CIDR
  (`kubectl get ciliumnode` or `talconfig.yaml` if it's ever changed). If
  this shows up on a pod that's been running a while, HA's own pending-config
  trial (see above) may have reverted a change — check for `pending` in
  `.storage/http` with `"error": "not_promoted"`.
- **Config change not taking effect on an already-running pod:** see the
  seed-config pattern above — bump `SEED_VERSION` (zigbee2mqtt/homeassistant)
  or `home-lab-ops/config-generation` (mosquitto).
