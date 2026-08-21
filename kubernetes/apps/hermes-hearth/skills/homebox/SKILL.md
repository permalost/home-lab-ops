---
name: homebox
description: "Homebox inventory API via curl. Items, locations, labels."
version: 0.1.0
author: community
license: MIT
platforms: [linux, macos, windows]
prerequisites:
  env_vars: [HOMEBOX_URL, HOMEBOX_API_KEY]
  commands: [curl]
metadata:
  hermes:
    tags: [Homebox, Inventory, API, Home-Automation]
    homepage: https://homebox.software
    related_skills: []
---

# Homebox

Homebox inventory REST API via curl and a bearer API key. As of v0.26,
items and locations are a single unified `entities` model — an entity's
`entityType.isLocation` flag is what makes it a "location" (box, shelf,
room) instead of an "item" stored inside one. There is no `/api/v1/items`
or `/api/v1/locations` — older docs describing those are stale.

## When to Use

- "What's in the garage shelf?" / "Which box has the spare SSDs?"
- "Add a new item to Homebox" / "Rename this location"
- "What location is `<item>` in?"
- Finding a location's UUID to wire into the ESL tag sync (see Pitfalls)

## Prerequisites

- `HOMEBOX_URL` — in-cluster:
  `http://homebox-svc.homebox.svc.cluster.local:8080` (already set in this
  deployment's env).
- `HOMEBOX_API_KEY` — Homebox UI: Settings → Manage API keys. Bearer token,
  format `hb_<random>`.

## How to Run

All calls: `curl -s -H "Authorization: Bearer $HOMEBOX_API_KEY" "$HOMEBOX_URL/api/v1/..." | python3 -m json.tool`
(`-s` keeps output clean).

## Quick Reference

| Action | Endpoint |
|---|---|
| Search entities | `GET /api/v1/entities?q=<term>` |
| Get one entity | `GET /api/v1/entities/{id}` |
| Location tree | `GET /api/v1/entities/tree?withItems=true` |
| Create entity | `POST /api/v1/entities` |
| Rename/update | `PATCH /api/v1/entities/{id}` (partial) or `PUT` (full replace) |
| Location label PNG | `GET /api/v1/labelmaker/location/{id}` |
| Entity types | `GET /api/v1/entity-types` |

## Procedure

### Find a location's UUID

```bash
curl -s -H "Authorization: Bearer $HOMEBOX_API_KEY" \
  "$HOMEBOX_URL/api/v1/entities/tree?withItems=true" | python3 -m json.tool
```

Flat array of top-level locations, each `{id, name, type: "location", children: [...]}`
— items nest as `type: "item"`, sub-locations as `type: "location"`. This is
also how to get the `location` UUID for `apps/home-automation/homeassistant/`'s
`esl_sync_labels` `tag_map`.

### Search

```bash
curl -s -H "Authorization: Bearer $HOMEBOX_API_KEY" \
  "$HOMEBOX_URL/api/v1/entities?q=ssd" | python3 -m json.tool
```

Matches items and locations by name/description; check each result's
`entityType.isLocation` to tell which.

### Get full detail on one entity

```bash
curl -s -H "Authorization: Bearer $HOMEBOX_API_KEY" \
  "$HOMEBOX_URL/api/v1/entities/<uuid>" | python3 -m json.tool
```

Locations include a `children` array of what's stored in them; items
include a `parent` object naming their containing location.

### Create an item

```bash
curl -s -X POST -H "Authorization: Bearer $HOMEBOX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Spare SSD", "description": "1TB NVMe", "parentId": "<location-uuid>"}' \
  "$HOMEBOX_URL/api/v1/entities" | python3 -m json.tool
```

Omit `entityTypeId` for a plain item — Homebox lazily creates the group's
default "Item" type on first use. To file something as a location instead,
pass the group's "Location" type id (from `GET /api/v1/entity-types`) as
`entityTypeId`.

### Rename or re-describe a location

```bash
curl -s -X PATCH -H "Authorization: Bearer $HOMEBOX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Garage Shelf A", "description": "Spare parts, updated"}' \
  "$HOMEBOX_URL/api/v1/entities/<uuid>" | python3 -m json.tool
```

This is what a physical ESL tag reacts to — `esl_sync_labels` polls hourly
and diffs the labelmaker PNG's hash, so this shows up on the tag within the
hour with no other action needed.

### Force an immediate tag redraw

Don't wait for the hourly poll — trigger the automation directly with the
`ha_call_service` tool: service `automation.trigger`, target entity
`automation.esl_sync_labels`. Uses `$HASS_TOKEN`, not `$HOMEBOX_API_KEY`.

## Pitfalls

- **Not the pre-v0.26 items/locations API** — see intro. `entityType.isLocation`
  is the only way to tell a location from an item now.
- **Label geometry is instance-wide**, not a query param on
  `/api/v1/labelmaker/*` — this deployment sets 360×184 to match the Solum
  Newton ESL tags' canvas (`apps/homebox/README.md`), so paper labels print
  at that size too.
- `PUT` replaces the whole entity; use `PATCH` for a partial edit like a
  rename, or unset fields get blanked.
- A 401 usually means `HOMEBOX_API_KEY` is wrong/unset; a connection error
  usually means `HOMEBOX_URL` or in-cluster DNS is wrong — check which
  before assuming the other.

## Verification

```bash
curl -s -H "Authorization: Bearer $HOMEBOX_API_KEY" "$HOMEBOX_URL/api/v1/status" | python3 -m json.tool
```

Expect `"health": true`.
