#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p inventory/private
./scripts/audit-docker-homepage-readiness.py > inventory/private/docker-homepage-readiness.json
./scripts/export-heimdall-safe.py --format json > inventory/private/heimdall-items.safe.json
./scripts/export-heimdall-safe.py --format csv > inventory/private/heimdall-items.safe.csv
if [ -f /mnt/appdata/NginxProxyManager/database.sqlite ]; then
  sqlite3 -cmd '.headers on' -cmd '.mode csv' /mnt/appdata/NginxProxyManager/database.sqlite \
    'select id, enabled, domain_names, forward_scheme, forward_host, forward_port, access_list_id, certificate_id, ssl_forced, caching_enabled, block_exploits, allow_websocket_upgrade from proxy_host order by id;' \
    > inventory/private/npm-proxy-hosts.safe.csv
fi
docker compose ls --format json > inventory/private/docker-compose-ls.json
printf 'Generated inventory/private/* at %s\n' "$(date -Is)"
