# Known issues & follow-up configuration — Homepage + Glance

Master checklist of everything not yet done, every known rough edge, and every
credential/route still to configure, across both dashboards. Priorities:
**P0** = do before/at public launch · **P1** = quality/reliability · **P2** = polish.

Cross-references: session worklog `20-2026-07-01-worklog.md`, ingress runbook
`21-cloudflare-ingress-runbook.md`, widget syntax `10-widget-recipes.md`,
Glance service `../../glance/README.md` + `../../glance/WORKLOG.md`.

---

## A. Homepage (`~/workspace/myServices/homepage`, port 33080)

### A1 (P0) — Widget credentials still missing
All `HOMEPAGE_VAR_*` below are **empty**; each token must be generated in that app's
own UI (they are not stored on disk / not in any compose file). Fill in the gitignored
`.env`, then `docker compose restart homepage`. Wire each on its card in
`/mnt/appdata/homepage/config/services.yaml` under a `widget:` block.

| Service | Env var(s) | Where to generate | Homepage `widget.type` |
|---|---|---|---|
| Portainer | `HOMEPAGE_VAR_PORTAINER_KEY` | Portainer → My account → API tokens | `portainer` (needs `env:` = endpoint id, `key`) |
| Jellyfin | `HOMEPAGE_VAR_JELLYFIN_API_KEY` | Dashboard → Advanced → API Keys | `jellyfin` (`url`,`key`) |
| Immich | `HOMEPAGE_VAR_IMMICH_API_KEY` | Account Settings → API Keys | `immich` (`url`,`key`,`version:2`) |
| Nextcloud | `HOMEPAGE_VAR_NEXTCLOUD_TOKEN` | Settings → Security → app password | `nextcloud` (`url`,`username`,`password`) |
| qBittorrent | `HOMEPAGE_VAR_QBITTORRENT_USERNAME/PASSWORD` | WebUI login creds | `qbittorrent` |
| Grafana (TeslaMate) | `HOMEPAGE_VAR_GRAFANA_USERNAME/PASSWORD` | Grafana login | `grafana` |
| AdGuard Home | `HOMEPAGE_VAR_ADGUARD_USERNAME/PASSWORD` | AdGuard admin creds (runs off-box) | `adguard` |
| Backrest | `HOMEPAGE_VAR_BACKREST_USERNAME/PASSWORD` | Backrest instance creds | `backrest` |
| Home Assistant | `HOMEPAGE_VAR_HOMEASSISTANT_TOKEN` | Profile → Long-lived access tokens | `homeassistant` |
| TrueNAS | `HOMEPAGE_VAR_TRUENAS_API_KEY` | TrueNAS → API Keys (**extra caution**) | `truenas` |
| Suwayomi | `HOMEPAGE_VAR_SUWAYOMI_USERNAME/PASSWORD` | Suwayomi basic-auth (if enabled) | `suwayomi` |
| Cloudflared | `HOMEPAGE_VAR_CLOUDFLARED_ACCOUNT_ID/TUNNEL_ID/API_TOKEN` | CF dashboard + API token | `cloudflared` |

Already wired this session (no action needed): **PhotoPrism, Netdata, Uptime-Kuma**.

Representative wiring (put under the service's card):
```yaml
    - portainer:
        widget:
          type: portainer
          url: http://axolotl.newhome:9000
          env: 1                       # endpoint id (usually 1 = local)
          key: "{{HOMEPAGE_VAR_PORTAINER_KEY}}"
    - jellyfin:
        widget:
          type: jellyfin
          url: http://axolotl.newhome:8096
          key: "{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}"
```

### A2 (P1) — `.env` has a duplicate `HOMEPAGE_VAR_UPTIME_KUMA_SLUG`
The template line (empty) and the appended `=all` line both exist. `env_file` takes the
last value (`all`), so it works, but remove the empty duplicate for cleanliness.

### A3 (P1) — services.yaml is now hand-curated; the generator will overwrite it
`scripts/generate-services-from-inventory.py` regenerates the whole catalog from
inventory and **does not preserve** the hand-added `widget:` blocks, dedup, or the
Jellyfin port fix. If you re-run it: (a) back up `services.yaml` first, then re-apply
the widget blocks, **or** (b) extend the generator to merge/keep an overrides file.
The curated snapshot lives in `config-template/config/services.yaml`.

### A4 (P2) — Catalog polish still open (from the auto-generation)
- Resolved 2026-07-18: the generator now allowlists actual HTTP container ports;
  DB, Redis, SOCKS, Shadowsocks, RPC-only, and unreachable control ports remain
  stat-only cards without `href` / `siteMonitor`.
- More near-duplicates remain (public-route card + Docker card for the same app, e.g.
  Open WebUI, API Conversion, AutoBangumi/Ani, TrueNAS/Truenas). Merge to one card
  with the best `href` + `siteMonitor` + `widget`.
- Hide noisy infra containers (Redis/Valkey/Postgres/mosquitto/notify-push/imaginary)
  or move them to a collapsed "Internal" group — they add stat cards but no UI to open.
- Replace remaining generic `icon: mdi-docker` with proper icons
  (`/images/dracula-icons/*` or `di:<name>` / `sh:<name>`).

### A5 (P1) — `axolotl.newhome` name resolution inside the container
Widgets and `siteMonitor` requests are made **from the Homepage container**. If
`axolotl.newhome` ever fails to resolve inside the container, widgets/monitors go red.
Fallback: use the LAN IP `192.168.10.13` instead, or add a compose `extra_hosts:` entry
`axolotl.newhome:192.168.10.13`.

### A6 (P1) — PhotoPrism / Netdata widget reachability
- PhotoPrism widget uses `username`+`password` to open a session against
  `http://axolotl.newhome:52342`. If you enable PhotoPrism 2FA or an app-password
  policy, switch to an app password. Public `https://photo.dfder.tw` also works if the
  local port isn't reachable from the container.
- Netdata widget hits `:19999`; if Netdata is later locked down or moved off host
  networking, update the URL / add auth.

### A7 (benign) — Log noise
- `Could not chown /app/config…` warnings are expected from the appdata mount perms;
  not fatal.
- docker-socket-proxy shows a HAProxy timeout warning; no functional impact observed.

---

## B. Glance (`~/workspace/myServices/glance`, port 33081)

### B1 (P1) — `docker-containers` widget transport
It reads `tcp://glance-dockerproxy:2375` (read-only proxy). Verified working. If a
future Glance release drops tcp sock support, fall back to a direct **read-only** socket
mount instead:
```yaml
# in docker-compose.yml (glance service) add:
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
# and in config: sock-path: /var/run/docker.sock
```

### B2 (P2) — Docker widget is noisy (shows all ~75 containers)
Group children under parents and/or hide helpers:
- Add labels on noisy containers: `glance.hide: "true"` (Redis/Postgres/valkey/etc.).
- Or set `hide-by-default: true` on the widget and opt-in with `glance.hide: "false"`
  on the ones you care about.
- Use `glance.parent` / `glance.id` labels to nest child containers under a stack.
- Add `glance.category` to split media/ai/infra.

### B3 (P1) — `server-stats` shows the container, not the host
Netdata (on Homepage) already covers true host metrics. If you want real host stats in
Glance, mount host paths into the Glance container and configure the widget's
mountpoints; otherwise treat this panel as indicative only.

### B4 (P2) — Theme HSL for `nord` / `tokyo-night` are community values
The first five presets use the official Glance community-theme values; `nord` and
`tokyo-night` use common community HSL and may want tweaking. Edit
`config/glance.yml` → `theme.presets`. Default theme is Dracula (top-level `theme:` keys).

### B5 (P1) — External-widget fragility
- `reddit` can be rate-limited/blocked by Reddit; if the widget errors, reduce
  subreddits or add `app-auth`. `markets` uses Yahoo symbols — verify `^TWII` (TAIEX)
  still resolves; swap symbols if a quote goes missing. `releases` is rate-limited
  without a token — set `GLANCE_GITHUB_TOKEN` in `.env`.
- `di:` icon slugs (dashboard-icons) — verify a few render (e.g. `di:truenas-scale`,
  `di:tachiyomi`, `di:open-webui`); swap to `sh:` (selfh.st) or a URL if any 404.

### B6 (P0 if exposed) — Glance auth
Glance's built-in auth is basic. If you expose `glance.dfder.tw`, put it behind
**Cloudflare Access** (see ingress runbook) and/or enable Glance `auth`:
```yaml
auth:
  secret-key: ${GLANCE_SECRET_KEY}    # ./glance secret:make
  users:
    df:
      password-hash: ${GLANCE_PW_HASH} # ./glance password:hash <pw>
```
`server.proxied: true` is already set so real client IPs come from `X-Forwarded-For`.

---

## C. Cross-cutting

### C1 (P0) — Public ingress (deferred)
`hp.dfder.tw` and `glance.dfder.tw` are **not live**. Full dashboard + API procedure,
including the mandatory **Cloudflare Access** auth (neither app has real auth), is in
`21-cloudflare-ingress-runbook.md`. Confirm `HOMEPAGE_ALLOWED_HOSTS` matches the exact
public + local hostnames before/after enabling.

### C2 (P1) — Backups
Neither dashboard's config is backed up yet.
- Homepage config: `/mnt/appdata/homepage/config` (+ `/images`).
- Glance config: `~/workspace/myServices/glance/config`.
Add both to **Backrest**. `.env` files hold the only copies of harvested/entered
secrets — include them (Backrest repo is encrypted) or store secrets in a vault.

### C3 (P1) — Both images are `:latest`
`ghcr.io/gethomepage/homepage:latest`, `glanceapp/glance:latest`, and the
socket-proxies float on `latest`. A `docker compose pull` can introduce a breaking
change. Consider pinning to a known-good tag, and take a config backup before pulling.
Glance especially is fast-moving — re-check the config schema after major bumps.

### C4 (P2) — Heimdall retirement (Stage 3, not started)
Only after both dashboards are accepted:
1. Back up `/mnt/appdata/heimdall`.
2. Back up both dashboard configs.
3. Repoint or retire the old Heimdall public route (whichever `*.dfder.tw` points to
   `:50080`) — via the ingress runbook.
4. Keep Heimdall container stopped-but-present for rollback for a while before removing.

### C5 (P1) — Self-monitoring
Add `hp.dfder.tw` / `:33080` and `glance.dfder.tw` / `:33081` to **Uptime-Kuma** so an
outage of the dashboards themselves is noticed.

### C6 (resolved 2026-07-17) — Git hygiene
Homepage and Glance deployment files are tracked separately from runtime state. `.env`
files, agent metadata, logs, and generated backups are excluded by the repository
`.gitignore`. Runtime Homepage config under `/mnt/appdata` remains outside git; the
secret-free snapshot in `config-template/config/` is the reviewable source of truth.

### C7 (P2) — Resource footprint
Now running two dashboards + two socket-proxies. Low, but watch memory if you later add
heavy widgets. Both proxies are `POST:0` (read-only) — keep it that way.

---

## D. Quick command reference
```bash
# Homepage
cd ~/workspace/myServices/homepage
docker compose restart homepage
curl -fsS http://127.0.0.1:33080/api/services | \
  python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d),'groups',sum(len(g['services']) for g in d),'cards')"
./scripts/scan-secrets.sh

# Glance
cd ~/workspace/myServices/glance
docker compose restart glance
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:33081/
docker logs glance 2>&1 | tail -20   # look for widget errors
```
