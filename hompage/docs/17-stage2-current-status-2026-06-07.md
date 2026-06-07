# Stage 2 Current Status Review — 2026-06-07

This document was created after an agent interruption to reconstruct the exact current state of the Homepage migration work.

## Executive state

Homepage Stage 2 is **partially implemented and locally running**.

- Homepage is deployed on axolotl via Docker Compose.
- Homepage is healthy and reachable locally on host port `33080`.
- Runtime config lives under `/mnt/appdata/homepage/config`.
- Dracula for Homepage theme is installed and active via `custom.css`, `color: gray`, and mounted image assets.
- `services.yaml` has been generated using a services.yaml-first strategy.
- Every running Docker container has a Homepage card with Docker status/stats wiring through `local-docker`.
- Public reverse proxy for `hp.dfder.tw` is **not yet completed**.
- Heimdall is still running and has not been modified or stopped.
- NPM route for `hp.dfder.tw` does not exist in the observed NPM SQLite DB.
- Nginx Proxy Manager container was not running during review; live ingress appears to involve `cloudflared`, not local NPM.

## Verified runtime status

Review time on axolotl: `2026-06-07T22:51:18+08:00`.

Docker Compose status under `~/workspace/myServices/hompage`:

```text
homepage               ghcr.io/gethomepage/homepage:latest            Up 20 hours (healthy)   0.0.0.0:33080->3000/tcp
homepage-dockerproxy   ghcr.io/tecnativa/docker-socket-proxy:latest   Up 20 hours             2375/tcp
```

Local HTTP check:

```text
http://127.0.0.1:33080/ -> HTTP 200
```

Homepage API services check:

```text
groups: 9
cards: 111
```

Group counts:

```text
Core Infrastructure: 21
Network & Ingress: 14
Observability: 6
AI & LLM: 24
Media: 11
Downloads & Network: 3
Photos & Files: 20
Databases & Admin: 5
Backup & Maintenance: 7
```

## Runtime files

Runtime config:

```text
/mnt/appdata/homepage/config/bookmarks.yaml
/mnt/appdata/homepage/config/custom.css
/mnt/appdata/homepage/config/custom.js
/mnt/appdata/homepage/config/docker.yaml
/mnt/appdata/homepage/config/kubernetes.yaml
/mnt/appdata/homepage/config/services.yaml
/mnt/appdata/homepage/config/settings.yaml
/mnt/appdata/homepage/config/widgets.yaml
```

Theme/image assets:

```text
/mnt/appdata/homepage/images/Dracula.png
/mnt/appdata/homepage/images/dracula-icons/*
```

The active `services.yaml` size at review was `35048` bytes and parsed successfully as YAML.

## Theme status

Theme selected: **Dracula for Homepage**.

Source:

- <https://github.com/dracula/homepage-app>
- <https://draculatheme.com/homepage-app>

Applied assets:

- `custom.css` from Dracula Homepage repo.
- `Dracula.png` background.
- Selected Dracula service icons.

Relevant settings:

```yaml
color: gray
headerStyle: underlined
background:
  image: /images/Dracula.png
  blur: sm
  saturate: 70
  brightness: 45
  opacity: 60
```

## Service catalog status

Generator script:

```text
scripts/generate-services-from-inventory.py
```

Generated report:

```text
docs/16-stage2-service-catalog-report.md
```

Catalog generation strategy:

1. Read running Docker containers from `inventory/private/docker-homepage-readiness.json`.
2. Read public route metadata from `inventory/private/npm-proxy-hosts.safe.csv` when available.
3. Read Heimdall safe export from `inventory/private/heimdall-items.safe.json`.
4. Generate a services.yaml-first Homepage catalog.
5. Every running container gets:
   - `server: local-docker`
   - `container: <container name>`
   - `showStats: true`
6. Cards with known host/public URL also get `href` and `siteMonitor`.
7. Secret-bearing widgets are intentionally not auto-enabled.

Review result:

```text
Running Docker containers connected: 74
Total Homepage service cards generated: 111
Public NPM routes considered: 44
Heimdall safe-export cards considered: 34
```

## Validation status

Executed during review:

```bash
./scripts/scan-secrets.sh
./scripts/check-homepage-labels.sh
```

Results:

```text
Secret scan passed.
Homepage-labeled containers: 0
```

Runtime YAML parse succeeded for all active YAML files.

Homepage logs show only non-fatal config ownership warnings:

```text
Warning: Could not chown /app/config; continuing anyway
Warning: Could not chown /app/config/logs
```

These warnings are expected from the current appdata mount permission behavior and did not block service startup.

Docker socket proxy logs show it is receiving read-only Docker API traffic from Homepage. There is a HAProxy timeout warning from docker-socket-proxy, but no current functional failure was observed.

## Public reverse proxy status

DF requested public reverse proxy with hostname:

```text
hp.dfder.tw
```

Current state:

- `HOMEPAGE_ALLOWED_HOSTS` includes `hp.dfder.tw`.
- Local Homepage listens on `0.0.0.0:33080`.
- No `hp.dfder.tw` route was found in the NPM SQLite DB.
- The expected `nginxproxymanager` container was not running during review.
- Ports previously associated with NPM UI / HTTP / HTTPS were not listening during review.
- `cloudflared` is running and likely relevant to current public ingress.

Important: public route is **not yet complete**. Do not claim `hp.dfder.tw` is live until explicitly verified from outside or through Cloudflare/NPM route configuration.

## Known open tasks

### P0 — Finish public ingress

Determine the actual current ingress control plane:

- If Cloudflare Tunnel controls `*.dfder.tw`, add `hp.dfder.tw -> http://localhost:33080` or equivalent route through Cloudflare Tunnel configuration/API.
- If NPM should control it, first restore/locate the actual NPM container/API path, then create route safely with existing wildcard certificate and access list.
- Do not direct-edit NPM SQLite unless there is no safer path and a DB backup/restart plan is prepared.

### P1 — Verify browser UI

After public route exists:

- Open local URL.
- Open `https://hp.dfder.tw`.
- Confirm Dracula styling and background render correctly.
- Confirm groups/tabs are usable with 111 cards.
- Check browser console for `/api/services`, `/api/widgets`, Docker status, and icon asset errors.

### P1 — Widget credentials

Current catalog connects every container/card, but secret-bearing widgets are not auto-enabled. Next step is to enable widgets one by one with reviewed `.env` credentials.

Candidate widgets:

- Portainer
- Nginx Proxy Manager, if NPM is active again
- Netdata
- Uptime Kuma
- Backrest
- Jellyfin
- Immich
- Nextcloud
- AdGuard Home
- qBittorrent
- PhotoPrism
- Home Assistant
- Gluetun
- Suwayomi
- TrueNAS, with extra caution
- Cloudflared, if API token is available

### P2 — Improve catalog quality

The generated catalog is complete but rough. It needs human polish:

- Merge duplicate public-route and container cards where appropriate.
- Hide internal DB/Redis/helper containers if the UI feels too noisy.
- Improve group classification and names.
- Prefer public/LAN URLs that are actually useful to DF.
- Replace generic `mdi-docker` icons where better Dracula icons exist.

## Safe continuation commands

To refresh inventory and regenerate full catalog:

```bash
cd ~/workspace/myServices/hompage
./scripts/generate-private-inventory.sh
./scripts/generate-services-from-inventory.py
docker compose restart homepage
curl -fsS http://127.0.0.1:33080/ >/dev/null
```

To inspect current Homepage API state:

```bash
curl -fsS http://127.0.0.1:33080/api/services | jq 'length, map({name, count: (.services|length)})'
```

To validate safety:

```bash
./scripts/scan-secrets.sh
./scripts/check-homepage-labels.sh
```

## Non-actions confirmed

- Heimdall was not stopped.
- Heimdall route was not replaced.
- Existing service compose files were not modified to add Homepage labels.
- NPM DB was not modified.
- No public route for `hp.dfder.tw` was created before confirming ingress path.
