# Official NPM Migration Plan

> Status: single authoritative plan, revised 2026-06-08. Target: migrate the current jlesage Nginx Proxy Manager data set to the official `jc21/nginx-proxy-manager` image. Do not use the removed NPMplus path for this migration.

## Decision

Use the official Nginx Proxy Manager image:

`docker.io/jc21/nginx-proxy-manager:2.15.1`

This keeps schema drift low and preserves a clean rollback path. NPMplus was removed from this plan because its own README says migration back to upstream is not supported, and it adds a different operating model.

## Current State

The readable source data set is:

`/mnt/appdata/NginxProxyManager`

If TrueNAS exposes the same data under another path, such as `/mnt/cachePool/appdata/NginxProxyManager`, set `SRC_CONFIG_DIR` explicitly before running the script. Do not rely on stale path notes.

Read-only SQLite inventory from the current data set:

| Item | Total rows | Active enabled rows | Current generated conf files |
|---|---:|---:|---:|
| Proxy hosts | 46 | 39 | 39 |
| Redirection hosts | 2 | 2 | 2 |
| 404 hosts | 2 | 1 | 1 |
| Streams | 3 | 1 | 1 |

The active stream is:

- `51443/tcp` and `51443/udp` -> `$ssl_preread_server_name:443`

Other important facts:

- Current jlesage container ports are `18080:8080`, `18443:4443`, `7818:8181`.
- Official container ports are `80`, `443`, `81`.
- The current jlesage generated nginx files contain `/config/log` paths and `listen 8080/4443`.
- `migrations_lock` and `knex_migrations_lock` are currently clear.
- `access/2` exists and is required for the `df basic auth` access list.
- The active Let's Encrypt wildcard certificate `*.dfder.tw` expires on `2026-08-17 14:05:59`.
- Cloudflare DNS credentials exist in both DB metadata and `letsencrypt/credentials/credentials-1`.

## Migration Strategy

Use a new target tree. Never mount the old jlesage tree directly into the official container.

Target layout:

```text
/mnt/appdata/NginxProxyManager_official/
├── data/
│   ├── database.sqlite
│   ├── keys.json
│   ├── access/
│   ├── custom_ssl/
│   ├── logs/
│   └── nginx/
└── letsencrypt/
```

The plan uses a conservative bootstrap config strategy:

1. Copy the SQLite DB, JWT keys, access files, custom cert files, and Let's Encrypt state.
2. Copy only generated nginx config directories needed for startup.
3. Sanitize those generated configs:
   - `/config/log` -> `/data/logs`
   - `listen 8080` -> `listen 80`
   - `listen 4443` -> `listen 443`
4. Expose active stream ports in the generated compose file.
5. Start the official container only after reviewing the generated target and compose.

This avoids the unsafe assumption that official NPM startup will rebuild all configs from DB. Official `backend/setup.js` does not do a full regenerate on normal startup.

## Files To Keep

- `NPM_MIGRATION_PLAN.md`: this plan.
- `scripts/migrate_to_official_npm.sh`: staging script for the official image.

All archive reports, NPMplus scripts, and old review files have been removed to prevent stale decisions.

## Script Usage

Dry-run:

```bash
bash scripts/migrate_to_official_npm.sh
```

Stage target data and compose:

```bash
bash scripts/migrate_to_official_npm.sh --execute
```

The script does not stop the old container and does not start the new one. It stages data and writes a compose artifact only.

Important overrides:

```bash
SRC_CONFIG_DIR=/mnt/appdata/NginxProxyManager
TARGET_ROOT=/mnt/appdata/NginxProxyManager_official
WORK_ROOT=/mnt/appdata/NginxProxyManager_migration
OFFICIAL_IMAGE=docker.io/jc21/nginx-proxy-manager:2.15.1
```

If rerunning against an existing target:

```bash
ALLOW_OVERWRITE_TARGET=1 bash scripts/migrate_to_official_npm.sh --execute
```

## Pre-Cutover Gates

Do not enter a maintenance window unless all gates pass:

- Script dry-run succeeds.
- Script `--execute` stages the target tree without errors.
- Generated compose includes:
  - `18080:80/tcp`
  - `18443:443/tcp`
  - `7818:81/tcp`
  - `51443:51443/tcp`
  - `51443:51443/udp`
- Staged nginx configs contain no `/config/` paths.
- Staged nginx configs contain no `listen 8080` or `listen 4443`.
- `docker compose -f <generated-compose> config` passes.
- Target `letsencrypt/live/*` symlinks resolve.
- Target credentials and private keys have restrictive modes.
- TrueNAS deployment authority is decided:
  - stop/disable old app through TrueNAS Apps UI if it is Apps-managed, or
  - stop the old compose service if it is standalone Docker Compose.

## Maintenance Window

1. Confirm the generated migration-input backup exists.
2. Confirm the staged target tree is complete.
3. Stop or disable the old jlesage NPM through the chosen deployment authority.
4. Start official NPM with the generated compose:

   ```bash
   docker compose -f /mnt/appdata/NginxProxyManager_migration/generated/<timestamp>/docker-compose.official.yml up -d
   ```

5. Watch logs until startup completes.
6. Run `nginx -t` inside the new container.
7. Verify admin UI on port `7818`.
8. Verify UI counts:
   - 39 active proxy hosts
   - 2 active redirection hosts
   - 1 active 404 host
   - 1 active stream
9. Verify external HTTP and HTTPS routes.
10. Verify `51443/tcp` and `51443/udp`.
11. Verify `teslamate.dfder.tw` basic auth still works.
12. Verify wildcard certificate loads and Cloudflare DNS renewal credential exists.
13. Update GoAccess to read the official target log path:

    `/mnt/appdata/NginxProxyManager_official/data/logs`

## Rollback

Rollback remains simple only if the old tree is untouched.

Trigger rollback if:

- Official container fails to start.
- `nginx -t` fails.
- Active proxy routes fail broadly.
- Active stream on `51443` fails.
- Certificates fail to load.

Rollback steps:

1. Stop the official container.
2. Keep the failed target tree for inspection.
3. Start or re-enable the old jlesage app.
4. Verify `18080`, `18443`, `7818`, and `51443`.
5. Keep the migration backup until the root cause is understood.

## Post-Cutover

Keep the old jlesage data tree and app definition for at least 7 days.

During the soak period:

- Confirm access logs are written under the official target.
- Confirm GoAccess reads the new log path.
- Confirm no route uses stale `/config` paths.
- Confirm Let's Encrypt renewal path works before deleting the old data.

## Source Evidence

- Official NPM latest release: `v2.15.1`, published 2026-06-03.
- Official setup requires `/data` and `/etc/letsencrypt`; stream ports must be exposed separately.
- Official advanced config documents `PUID/PGID`, healthcheck, and `/data/nginx/custom`.
- Official startup runs migrations and setup, but not a full config regenerate.
- jlesage image persists everything under `/config`, changes ports to `8181/8080/4443`, rewrites `/data/logs` to `/config/log`, and clears migration locks at startup.
- NPMplus README warns that migrating back to original upstream is not possible.

Primary references:

- https://github.com/NginxProxyManager/nginx-proxy-manager
- https://nginxproxymanager.com/setup/
- https://nginxproxymanager.com/advanced-config/
- https://github.com/jlesage/docker-nginx-proxy-manager
- https://github.com/ZoeyVid/NPMplus
