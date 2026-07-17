# Glance build worklog

## 2026-07-01 — Initial deployment

### Goal
Add a Glance dashboard as a standalone Docker service alongside Homepage and
Heimdall, integrate homelab services, and bundle the community's most popular
themes as owner-selectable presets.

### Decisions
- **Deployment**: Docker Compose in `~/workspace/myServices/glance`, host port
  `33081`, config hot-mounted at `./config`.
- **Docker access**: dedicated read-only `docker-socket-proxy` (`glance-dockerproxy`)
  reached over `tcp://glance-dockerproxy:2375`, mirroring Homepage's posture. The
  Glance container is on an `internal` network (to the proxy) + an `egress` bridge
  (for weather/RSS/reddit/GitHub).
- **Shape**: multi-page — `Home` (personal start page) + `Infra` (ops board).
- **Theme**: default **Dracula** to match Homepage; 7 presets via the live picker.
- **Ingress**: `glance.dfder.tw` deferred by owner; documented in the Homepage
  ingress runbook (`../homepage/docs/21-cloudflare-ingress-runbook.md`).

### Files created
- `docker-compose.yml`, `.env`, `.env.example`, `.gitignore`
- `config/glance.yml`
- `README.md`, `WORKLOG.md`

### Verification (all passed)
- `docker compose config` valid; `up -d` clean; **0 errors / 0 warnings** in logs.
- `GET /` and `GET /infra` → HTTP 200.
- Home content (`/api/pages/home/content/`, ~102 KB): weather (Taipei), markets
  (TAIEX/Bitcoin), RSS (Hacker News/The Verge), reddit (selfhosted), bookmarks,
  releases — all rendered.
- Infra content (`/api/pages/infra/content/`, ~142 KB): **docker-containers widget
  populated with live host containers** (nextcloud, teslamate, immich, qbittorrent,
  photoprism, vaultwarden, jellyfin, portainer, netdata, heimdall, …) — confirms
  the socket-proxy link works and Glance sees all containers, not just its own.
- All 7 theme presets present in served HTML.

### Known follow-ups
- Visual/browser QA of theme rendering (open the URL and cycle the picker).
- Optionally hide helper/DB containers from the Infra docker widget via
  `glance.hide` labels.
- Wire `glance.dfder.tw` public ingress + Cloudflare Access when ready.
- `server-stats` reflects the Glance container's view; add host mounts if true
  host metrics are wanted (Netdata already covers host metrics on Homepage).
