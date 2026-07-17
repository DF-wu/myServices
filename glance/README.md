# DF Glance

A second homelab dashboard built on [glanceapp/glance](https://github.com/glanceapp/glance),
deployed side-by-side with Homepage (`:33080`) and Heimdall (`:50080`) as an
independent Docker Compose service. Glance complements Homepage: Homepage is the
curated service catalog; Glance is a fast **personal start page + live ops board**.

## Status

- Deployed locally on axolotl, host port **`33081`** → container `8080`.
- Local URL: <http://127.0.0.1:33081/> (also `http://axolotl.newhome:33081/`).
- Public ingress (`glance.dfder.tw`) is **deferred by owner decision** — see
  `../homepage/docs/21-cloudflare-ingress-runbook.md`.
- Docker access is via a **read-only `docker-socket-proxy`** (`glance-dockerproxy`),
  same security posture as Homepage. The UI container never touches the raw socket.

## Layout

| File | Purpose |
|---|---|
| `docker-compose.yml` | Glance + read-only docker-socket-proxy, two networks (internal + egress). |
| `.env` | `GLANCE_HOST_PORT`, `TZ`, optional `GLANCE_GITHUB_TOKEN`. Gitignored. |
| `.env.example` | Template for `.env`. |
| `config/glance.yml` | All pages, widgets, and theme presets. |
| `WORKLOG.md` | Build log, decisions, and verification results. |

## Pages

- **Home** — clock (multi-timezone), calendar, weather (Taipei), search bar with
  bangs, Hacker News + Reddit (`selfhosted` / `homelab` / `LocalLLaMA`) tab group,
  Tech News RSS, markets (S&P 500, TAIEX, NVDA, TSLA, BTC, ETH), GitHub releases,
  and service bookmarks.
- **Infra** — host `server-stats`, **`docker-containers`** (live, via socket-proxy),
  and two `monitor` panels (Core Infra + Apps & Media) pointing at LAN/public URLs.

## Themes (owner-selectable)

Default theme is **Dracula** (matches Homepage). The theme **picker** (top-right of
the UI) switches between bundled community presets at runtime; the choice is stored
per-browser. Bundled presets:

`dracula`, `catppuccin-mocha`, `catppuccin-macchiato`, `gruvbox-dark`,
`kanagawa-dark`, `nord`, `tokyo-night`.

Verified HSL values (from the Glance community themes doc) are used for the first
five; `nord` and `tokyo-night` use common community values and can be tweaked in
`config/glance.yml` under `theme.presets`.

## Operate

```bash
cd ~/workspace/myServices/glance
docker compose up -d          # start
docker compose restart glance # apply config changes (config is hot-mounted)
docker compose logs -f glance # logs
docker compose down           # stop
```

Config edits: change `config/glance.yml`, then `docker compose restart glance`.

## Known issues & follow-ups

Glance-specific items (docker-widget transport fallback, hiding noisy containers,
`server-stats` host metrics, theme HSL tweaks, external-widget fragility, auth when
exposed) and all cross-cutting items (ingress, backups, `:latest` pinning, git hygiene)
are consolidated in the master checklist:
`../homepage/docs/22-known-issues-and-followups.md` (section B + C).

## Notes

- The `docker-containers` widget reads from `tcp://glance-dockerproxy:2375`. To
  hide noisy helper containers, add `glance.hide: "true"` labels on them or set
  `hide-by-default: true` and opt-in with `glance.hide: "false"`.
- `releases` runs token-less; set `GLANCE_GITHUB_TOKEN` in `.env` to raise the
  GitHub rate limit.
