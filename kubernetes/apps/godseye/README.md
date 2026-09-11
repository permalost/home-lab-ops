# godseye

[God's Eye View](https://github.com/bilawalsidhu/gods-eye-view): CesiumJS globe over
live public data — flights, military ADS-B, satellites, earthquakes, CCTV, radio.
Built on `webapp/base` + `httproute`.

Runs from [permalost/gods-eye-view](https://github.com/permalost/gods-eye-view)
(`homelab` branch), not upstream directly: upstream ships no Dockerfile and no
production server, only `vite dev`/`build`/`preview`. The fork adds a Dockerfile
and patches `vite.config.js` so the data-proxy middleware (Vite-only, registered
per-plugin) survives under `vite preview` — see that repo's commit history on
`homelab` for what and why.

## Configuration

- **Namespace:** `godseye`
- No PVC — the only on-disk state is a satellite TLE cache that re-downloads
  harmlessly on restart.
- Image tag is pinned in `kustomization.yaml`'s `images:` block to a fork commit
  SHA + date (from the fork's `docker-publish.yml`), not `latest` — upstream
  moves fast, re-syncing the fork is a deliberate act.
- Keyless by design for now: flights (OpenSky anon), military ADS-B (adsb.lol),
  satellites (CelesTrak), earthquakes (USGS), CCTV, and radio all work with no
  API keys. TomTom/FIRMS/Cesium ion/Google 3D Tiles/OpenAI voice are unconfigured
  and simply won't appear — see the fork's `.env.example` if adding them later.

## Ingress / Exposure

Exposed via the `httproute` component at `${subdomain}.${domain}`
(`godseye.orion.norseamerican.com`). **LAN-only** — orion's Gateway has no path
in from the internet (external-dns writes to Pi-hole, not public DNS). No auth
in front — anything on the LAN that can reach the Gateway can use this app, so
don't add metered API keys without also adding an auth layer.

## Troubleshooting

- **"Blocked request. This host is not allowed."** — the fork's
  `vite.config.js` widens `allowedHosts` only when `HOST=0.0.0.0`; confirm the
  Dockerfile still sets that env var if this shows up after a fork resync.
- **A data layer never loads under `vite preview` but works if you clone the
  fork and run `npm run dev`** — a new upstream proxy plugin was added without
  a `configurePreviewServer` hook and slipped past the fork's
  `mirrorConfigureServerToPreview()` (e.g. it touches something on the server
  object besides `.middlewares`). Check the specific plugin in `vite.config.js`.
