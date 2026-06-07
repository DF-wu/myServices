# Service Catalog Design

This document defines how to convert the current homelab into Homepage groups. It intentionally avoids storing secrets.

## Catalog sources

Use these sources in order:

1. Docker Compose projects and running containers from axolotl.
2. Heimdall `items` table for existing human-facing links.
3. Nginx Proxy Manager proxy host DB for public route inventory.
4. Manual DF decisions for what should be visible, hidden, grouped, or protected.

Generated private inventory is stored under `inventory/private/` and ignored by git.

## Proposed group taxonomy

| Group | Examples | Homepage strategy |
|---|---|---|
| Core Infrastructure | Portainer, NPM, cloudflared, TrueNAS, Home Assistant, AdGuard | Curated cards; widgets only if secrets available. |
| Observability | Netdata, Uptime Kuma, GoAccess, Speedtest | Curated widgets, status-heavy layout. |
| AI & LLM | Open WebUI, new-api, CRS, CCR, api-conversion, MetaMCP, n8n | Mostly cards + siteMonitor; widgets via customapi only if useful. |
| Media | Jellyfin, Jellyseerr, MoonTV, Suwayomi | Widgets for Jellyfin/Seerr/Suwayomi when credentials are available. |
| Downloads & Network | qBittorrent, Jackett, Gluetun proxies, Aria2 | Keep sensitive download tools protected; widget only for selected qBittorrent/Gluetun. |
| Photos & Files | Nextcloud, Immich, PhotoPrism, AList | Good widget candidates. |
| Databases & Admin | MariaDB, phpMyAdmin, pgAdmin | Cards only; avoid exposing publicly. |
| Backup & Maintenance | Backrest, Watchtower-like services | Backrest widget is useful. |
| External Links | GitHub, external research tools, docs | Bookmarks, not services. |

## Widget candidates by priority

### High priority

- Portainer: Docker overview.
- Nginx Proxy Manager: enabled/disabled/total proxy hosts.
- Netdata: warnings/criticals.
- Uptime Kuma: status page summary.
- Backrest: backup success/failure.
- Jellyfin: media counts / now playing.
- Immich: users/photos/videos/storage.
- Nextcloud: free space / active users / file counts.
- AdGuard: DNS queries/blocked/latency.

### Medium priority

- qBittorrent: leech/download/seed/upload.
- PhotoPrism: albums/photos/videos/people.
- Home Assistant: selected states/templates.
- Gluetun: public IP/region for selected VPN containers.
- Suwayomi: read/unread/download counts.
- TrueNAS: load/uptime/alerts; treat with caution because the host is high-importance.
- Tailscale: selected device status.

### Low priority or card-only

- LLM gateway services where no official widget exists: use `siteMonitor` or `customapi` only if a stable health endpoint exists.
- Databases/admin tools: card only, protected route.
- One-off external links: bookmarks.

## Heimdall conversion rules

Heimdall entries should not be blindly converted. Apply these rules:

1. If the item is an active homelab app, create a service card.
2. If the app is Docker-managed and safe to label, add Docker labels during Phase 2.
3. If the app has a Homepage widget and requires secrets, add a curated `services.yaml` entry using env placeholders.
4. If the item is external, make it a bookmark.
5. If the item is duplicated, stale, or points to an old host, ask DF before including.
6. Do not import Heimdall descriptions by default because local inspection found descriptions may contain credentials or operational notes.

## Icon strategy

Prefer built-in icon sources through Homepage:

- Dashboard Icons names: `jellyfin.svg`, `portainer.svg`, etc.
- Simple Icons: `si-github`, etc.
- Material Design Icons: `mdi-*` for generic infrastructure.
- Local icons mounted under `/app/public/icons` only for missing custom icons.

Avoid copying Heimdall's entire icon directory unless DF specifically wants exact visual parity. Exact icon migration is less important than a clean, maintainable catalog.

## Discovery rollout batches

Batch labels in this order:

1. Low-risk informational services with no secrets: Speedtest, static pages, GoAccess-like dashboards.
2. Core management cards without widget secrets: Portainer/NPM/Netdata cards only.
3. Media stack cards.
4. Storage/photos stack cards.
5. AI/LLM services.
6. Download/VPN/admin tools last, with route protection verified.

After each batch, check Homepage logs and UI before continuing.
