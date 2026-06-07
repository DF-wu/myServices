# Target Design

## Design principles

The target dashboard should be both beautiful and operationally useful. The maintainable split is:

1. **Docker labels for discovery and non-secret metadata**: group, name, icon, href, description, weight, optional siteMonitor.
2. **YAML for curated high-value services and any secret-bearing widgets**: API keys and passwords via environment placeholders.
3. **Bookmarks for external or low-operational links**: GitHub, documentation, external services, one-off tools.
4. **Small CSS only**: use Homepage settings first; avoid JS unless necessary.

This avoids the two common failure modes: a giant hand-maintained `services.yaml` that rots, or labels full of secrets and fragile widget config.

## Proposed architecture

```text
Browser
  -> Nginx Proxy Manager / Cloudflare Tunnel / VPN boundary
    -> homepage:3000
      -> /app/config/*.yaml
      -> dockerproxy:2375 (read-only Docker API)
        -> /var/run/docker.sock:ro
      -> internal service APIs for widgets
```

Homepage should run as its own stack under `~/workspace/myServices/homepage`, with runtime config under `/mnt/appdata/homepage/config` or `./config` depending DF's preference. For Portainer-style long-term persistence, `/mnt/appdata/homepage/config` is recommended.

## Security model

Homepage has no authentication. The route must be one of:

- **Private only**: reachable only on LAN/Tailscale; simplest and safest.
- **Public URL protected by NPM Access List / Basic Auth**: easy, but credentials and UX need review.
- **Public URL protected by Cloudflare Access**: stronger identity gate, slightly more moving parts.
- **Public but unauthenticated**: not recommended and should not be used.

Docker access should use `docker-socket-proxy`, not direct socket mount. Even read-only Docker metadata can expose environment variable names, labels, image names, ports, and operational details, so only Homepage should reach the proxy network.

## Suggested Homepage settings

Recommended starting point:

```yaml
title: DF Homelab
description: Service cockpit
language: zh-Hant
theme: dark
color: slate
headerStyle: boxedWidgets
statusStyle: dot
iconStyle: theme
target: _blank
fullWidth: true
maxGroupColumns: 6
useEqualHeights: true
disableIndexing: true
quicklaunch:
  searchDescriptions: true
  provider: duckduckgo
  target: _blank
```

Recommended visual direction: dark, clean, slightly glassy, not heavy cyberpunk. Homepage's built-in `background`, `cardBlur`, `headerStyle`, `layout`, and `iconStyle` are enough for a polished UI. `custom.css` should only add subtle card opacity/border/readability improvements.

## Proposed tabs and groups

Use tabs to avoid a single endless wall of cards.

| Tab | Groups | Purpose |
|---|---|---|
| `Core` | Core Infrastructure, Network & Ingress, Observability | Things needed to operate the homelab itself. |
| `AI` | AI & LLM, Automation | ChatStack, LLM gateways, RAG/tooling, n8n. |
| `Media` | Media, Downloads, Manga/Anime | Jellyfin, Jellyseerr, qBittorrent, Jackett, Suwayomi, MoonTV, etc. |
| `Data` | Storage & Photos, Databases, Admin Tools | Nextcloud, Immich, PhotoPrism, TrueNAS, MariaDB, pgAdmin, phpMyAdmin. |
| `External` | Public Links, Docs, Accounts | GitHub and external tools that are not homelab services. |

Suggested group names should remain stable because Homepage layout keys refer to group names exactly. Avoid using the same group name for services and bookmarks; upstream warns this can cause unexpected behavior.


## DF-selected catalog model

DF selected a **services.yaml-first** catalog model. Docker labels should be treated as optional helpers rather than the main source of truth. Keep `docker.yaml` enabled for Docker status/stats, but build the primary dashboard in curated YAML so all services can be grouped, ordered, and reviewed in one place.

For services with no official widget, add a normal service card with `href`, `description`, icon, and where useful `siteMonitor`. For services with an official widget, add the widget in `services.yaml` and use `HOMEPAGE_VAR_*` placeholders for secrets.

## Automatic discovery policy

There are three levels of migration maturity:

### Level A — Curated YAML first

Start with `services.yaml` for key services. Lowest risk. Good for first launch. Downside: more hand-maintenance.

### Level B — Labels for cards, YAML for secrets

Preferred target. Add labels to compose files for cards and status. Keep secret-bearing widget configs in YAML or `.env` placeholders. This reduces card maintenance without leaking credentials into labels.

### Level C — Labels for cards and widgets

Use only for widgets that require no secrets, or where the widget's values are non-sensitive. Avoid for API keys/passwords.

## Label standard

Use these labels on Docker services during Phase 2:

```yaml
labels:
  - homepage.group=Media
  - homepage.name=Jellyfin
  - homepage.icon=jellyfin.svg
  - homepage.href=https://example.invalid
  - homepage.description=Media server
  - homepage.siteMonitor=http://jellyfin:8096
  - homepage.weight=10
```

For services with Docker stats, discovery can infer server/container. For manual YAML entries, use:

```yaml
server: local-docker
container: jellyfin
showStats: true
```

## Widget secret policy

Secret values must be placeholders:

```yaml
widget:
  type: jellyfin
  url: http://jellyfin:8096
  key: "{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}"
```

The actual value lives in `.env`:

```bash
HOMEPAGE_VAR_JELLYFIN_API_KEY=...
```

Do not put this into a Docker label.

## Network URL policy

Each service may need two URLs:

- `href`: the URL DF clicks in the browser, usually public/reverse-proxied or LAN/Tailscale friendly.
- `widget.url` / `siteMonitor`: the URL Homepage container can reach. This is often an internal Docker hostname, LAN host:port, or reverse-proxy bypass URL.

Do not assume a public URL works from inside Homepage. Phase 2 must test from inside the container.

## Persistence

Recommended:

```text
/mnt/appdata/homepage/config
  settings.yaml
  services.yaml
  widgets.yaml
  bookmarks.yaml
  docker.yaml
  kubernetes.yaml
  custom.css
  custom.js
  logs/
```

The config directory should be backed up with the rest of appdata. Avoid storing generated private inventories in the runtime config directory.
