# Phase 1 Research Notes

Last researched: 2026-06-06. Upstream repo snapshot inspected locally: `gethomepage/homepage` commit `bd4f809`, package version `1.13.1`.

## Homepage core model

Homepage is a Next.js-based, YAML-configured application dashboard. Its official deployment path for this homelab should be Docker Compose with a mounted `/app/config` directory. The core config files are:

| File | Role |
|---|---|
| `settings.yaml` | Application-level settings: title, language, theme/color, layout, tabs, quick launch, providers, status style, docker stats, indexing, etc. |
| `services.yaml` | Manually curated service cards, grouped and optionally nested. Supports service widgets, Docker integration (`server` + `container`), `siteMonitor`, `ping`, `showStats`, icons, descriptions. |
| `widgets.yaml` | Top information widgets: resources, search, datetime, weather, glances, etc. |
| `bookmarks.yaml` | Lightweight grouped links without service status/widgets. Suitable for external links or non-operational shortcuts. |
| `docker.yaml` | Docker instance definitions for local/remote Docker API or socket. Required for Docker status/stats and Docker label service discovery. |
| `kubernetes.yaml` | Kubernetes discovery/stat mode. Not the primary path for current axolotl Docker homelab, but useful if future K8s is introduced. |
| `custom.css` / `custom.js` | Optional customization. Use sparingly; heavy customization becomes maintenance debt. |

Official references inspected:

- Homepage Docker install: `docs/installation/docker.md`, <https://gethomepage.dev/installation/docker/>
- Installation security / `HOMEPAGE_ALLOWED_HOSTS`: `docs/installation/index.md`, <https://gethomepage.dev/installation/>
- Docker configuration and service discovery: `docs/configs/docker.md`, <https://gethomepage.dev/configs/docker/>
- Services configuration: `docs/configs/services.md`, <https://gethomepage.dev/configs/services/>
- Settings: `docs/configs/settings.md`, <https://gethomepage.dev/configs/settings/>
- Bookmarks: `docs/configs/bookmarks.md`, <https://gethomepage.dev/configs/bookmarks/>
- Info widgets: `docs/configs/info-widgets.md`, <https://gethomepage.dev/configs/info-widgets/>
- Custom CSS/JS: `docs/configs/custom-css-js.md`, <https://gethomepage.dev/configs/custom-css-js/>
- Kubernetes discovery: `docs/configs/kubernetes.md`, <https://gethomepage.dev/configs/kubernetes/>
- Troubleshooting: `docs/troubleshooting/index.md`, <https://gethomepage.dev/troubleshooting/>

## Docker deployment facts

Homepage's Docker Compose example requires:

```yaml
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    ports:
      - 3000:3000
    volumes:
      - /path/to/config:/app/config
    environment:
      HOMEPAGE_ALLOWED_HOSTS: example.com
```

As of Homepage v1.0, `HOMEPAGE_ALLOWED_HOSTS` is required for hosts other than `localhost` / `127.0.0.1`. It must exactly include the hostnames and ports used to access Homepage. `*` disables the check but is explicitly not recommended upstream.

Homepage has no built-in authentication layer and upstream explicitly recommends deploying it behind a reverse proxy with authentication, TLS, or behind VPN. Because this dashboard will expose operational metadata and potentially widget-derived personal/system information, it must not be published unauthenticated.

## Docker socket and automatic discovery

Homepage supports Docker integration by direct socket or HTTP API. Direct socket mount works, but upstream notes it requires Homepage to run as root or be in the Docker group. For this homelab the safer design is:

```yaml
homepage -> docker-socket-proxy -> /var/run/docker.sock:ro
```

Use `ghcr.io/tecnativa/docker-socket-proxy` with only read permissions needed by Homepage:

```yaml
CONTAINERS=1
SERVICES=1
TASKS=1
POST=0
```

In `docker.yaml`:

```yaml
local-docker:
  host: dockerproxy
  port: 2375
```

Once Docker is configured, Homepage automatically discovers containers whose labels begin with `homepage.`. A minimum useful label set is:

```yaml
labels:
  - homepage.group=Media
  - homepage.name=Jellyfin
  - homepage.icon=jellyfin.svg
  - homepage.href=https://example.invalid
  - homepage.description=Media server
```

Widgets can also be configured by labels:

```yaml
labels:
  - homepage.widget.type=jellyfin
  - homepage.widget.url=http://jellyfin:8096
  - homepage.widget.key={{HOMEPAGE_VAR_JELLYFIN_API_KEY}}
```

However, Docker labels are visible via `docker inspect`. Therefore **do not store secrets directly in labels**. The safer policy is: labels only for non-secret card metadata; secrets live in config files via environment substitution.

Homepage supports multiple widgets per service using `homepage.widgets[0].type=...`, array fields as strings such as `homepage.widget.fields=["field1","field2"]`, and per-instance labels using `homepage.instance.<instanceName>.*` when `instanceName` is set in `settings.yaml`.

Discovered service ordering uses `weight`; default discovered weight is `0`, configured service weight is roughly index-based. Use explicit `homepage.weight` where order matters.

## Service widgets and information panels

Homepage supports a large set of service widgets. The ones immediately relevant to DF's homelab include:

| Service | Homepage widget type | Notes |
|---|---|---|
| AdGuard Home | `adguard` | Uses UI username/password. |
| Backrest | `backrest` | Can show backup success/failure/plan metrics. |
| Cloudflare Tunnel | `cloudflared` | Requires limited Cloudflare API token with tunnel read permission. |
| Gluetun | `gluetun` | Requires Gluetun HTTP control server; can show public IP/region. |
| Grafana | `grafana` | Useful for TeslaMate Grafana if credentials are available. |
| Home Assistant | `homeassistant` | Needs long-lived access token; can show custom states/templates. |
| Immich | `immich` | Needs API key with server statistics permission; version 2 for modern Immich. |
| Jellyfin | `jellyfin` | Needs Jellyfin API key; modern versions may need widget `version: 2`. |
| Jellyseerr / Overseerr | `seerr` | Use `type: seerr`; legacy names are aliases. |
| Netdata | `netdata` | Shows warning/critical counts. |
| Nextcloud | `nextcloud` | Can use NC-Token or username/password; maximum field limits apply. |
| Nginx Proxy Manager | `npm` | Uses admin UI credentials. Good for proxy host counts. |
| PhotoPrism | `photoprism` | Prefer app password over account password. |
| Portainer | `portainer` | Requires environment ID and API key. |
| qBittorrent | `qbittorrent` | Uses Web UI credentials. |
| Speedtest Tracker | `speedtest` | Depends on which speedtest implementation/version is running. |
| Suwayomi | `suwayomi` | Optional username/password. |
| Tailscale | `tailscale` | Requires Tailscale API access token and device ID. |
| TrueNAS | `truenas` | API key recommended; be careful because TrueNAS is high-importance infrastructure. |
| Uptime Kuma | `uptimekuma` | Requires status page slug; not full API. |
| Custom APIs | `customapi` | Good for unsupported internal APIs. |
| IFrame | `iframe` | Browser-side only, not proxied; use sparingly. |

Information widgets relevant to the landing page:

- `resources`: container's own CPU/memory/disk, plus mounted disk paths. It does not equal host-level stats unless mounts make relevant resources visible.
- `glances`: better for host-level metrics if Glances is installed in web server mode.
- `search`: supports Google/DuckDuckGo/Bing/Baidu/Brave/custom and multi-provider dropdown.
- `datetime`: locale-aware time/date display.
- `openmeteo`: recommended weather widget, no API key needed.

## Secrets handling

Homepage config supports environment substitution:

- `HOMEPAGE_VAR_XXX` replaces `{{HOMEPAGE_VAR_XXX}}` in config files.
- `HOMEPAGE_FILE_XXX` reads a file and replaces `{{HOMEPAGE_FILE_XXX}}`.

Recommended policy:

1. Public/non-sensitive metadata may live in Docker labels or YAML.
2. API keys/passwords/tokens must live in `.env` or secret files and be referenced as placeholders.
3. Do not put tokens in Docker labels.
4. Do not commit `.env`, generated inventories, or secret files.

## Visual design capabilities

Homepage supports a good-looking dashboard without heavy CSS. Use built-in options first:

- `theme: dark`
- color palette such as `slate`, `zinc`, `indigo`, `blue`, `cyan`, etc.
- `background` with opacity/blur/saturation/brightness.
- `cardBlur`
- `headerStyle: clean` / `boxedWidgets` / `underlined` / `boxed`
- `fullWidth`, `maxGroupColumns`, `layout`, tabs, per-group columns.
- `iconStyle: theme` to avoid loud gradients for prefixed icons.

Use `custom.css` only for small polish, e.g. card opacity, subtle border, or background readability. Avoid custom JS unless DF explicitly wants behavior not available upstream.

## Debug and validation methods

Official troubleshooting recommends:

- Check `config/logs/homepage.log` and `docker logs homepage`.
- Check browser console.
- Set `LOG_LEVEL=debug` when diagnosing.
- Widget URLs should not end with `/` or include extra API paths; the widget appends its own paths.
- Every service with widgets should have unique service name and unique group/subgroup names.
- Test network reachability from inside the Homepage container, not only from host:

```bash
docker exec homepage ping SERVICE_HOST_OR_IP
```

- If needed, install curl in the running container for temporary diagnostics:

```bash
docker exec -it homepage sh -lc 'apk add --no-cache curl && curl -vk http://service:port'
```

For this project, Phase 2 should add a deterministic smoke test script that checks:

```bash
docker compose config
cd ~/workspace/myServices/hompage && docker compose up -d
sleep 10
docker logs --tail 200 homepage
curl -fsS http://127.0.0.1:3000/ >/dev/null
```

## Heimdall migration research

Current Heimdall is running on axolotl with config mounted at `/mnt/appdata/heimdall:/config`, using `/mnt/appdata/heimdall/www/app.sqlite`.

Relevant SQLite tables:

```sql
items(id, title, colour, icon, url, description, pinned, "order", type, user_id, class, appid, appdescription, role, ...)
applications(appid, name, icon, website, description, enhanced, tile_background, class, ...)
item_tag(item_id, tag_id, ...)
```

Important discovery: Heimdall `items.description` may contain credentials, API keys, or operational notes. Therefore migration scripts must **not export descriptions by default**. Export `title`, `url`, `icon`, `appid`, `order`, `type`, and tag mapping first. Human review can later decide which descriptions are safe to rewrite.

Heimdall type/tag behavior observed locally:

- `type=0`: dashboard item / app shortcut.
- `type=1`: tag/category-like item.
- Most current dashboard items are tagged under `app.dashboard`.

Homepage mapping options:

| Heimdall data | Homepage target |
|---|---|
| Operational app/service hosted in Docker | Docker labels for `group/name/icon/href`, plus manually curated widget in YAML if secrets needed. |
| Important service with API widget | `services.yaml` entry with `widget` and env placeholders. |
| External/non-operational link | `bookmarks.yaml`. |
| Duplicate/old Heimdall tile | Review and likely drop or consolidate. |
| Heimdall app icon | Prefer Dashboard Icons / Simple Icons by name; local icons only if no upstream icon exists. |
| Heimdall description | Do not auto-migrate; rewrite manually if useful. |

## Current homelab observations for planning

Axolotl runs Docker Compose stacks primarily through Portainer-generated `/data/compose/*` paths and a source repository at `~/workspace/myServices`. Current stacks include media, AI/chat, storage, observability, reverse proxy, automation, backup, and VPN/proxy services.

No current container has Homepage labels yet. Therefore automatic discovery requires adding labels gradually to compose files/stacks during Phase 2, or starting with a curated `services.yaml` and migrating labels later.

Nginx Proxy Manager exists and has a SQLite database at `/mnt/appdata/NginxProxyManager/database.sqlite`. It can provide a route inventory, but changing proxy routes must wait until Phase 2 and DF confirmation.
