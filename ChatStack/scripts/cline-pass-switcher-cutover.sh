#!/usr/bin/env bash
# Point the new-api "cline pass" channel at cline-pass-switcher (or back at api.cline.bot).
#
# Usage:
#   scripts/cline-pass-switcher-cutover.sh [--wait SECONDS]   # default: wait up to 600s for the switcher
#   scripts/cline-pass-switcher-cutover.sh --rollback          # restore the direct api.cline.bot channel
#   scripts/cline-pass-switcher-cutover.sh --status            # print the channel's current base_url
#
# Idempotent. Secrets are read from the switcher's config.json on the host, nothing is stored here.
# Run on the docker host after the ChatStack stack has been (re)deployed from Portainer.
set -euo pipefail

CHANNEL_ID="${CHANNEL_ID:-316}"
PG_CONTAINER="${PG_CONTAINER:-chatstack-postgres17-pgvector}"
PG_DB="${PG_DB:-veloera_db}"
NEWAPI_CONTAINER="${NEWAPI_CONTAINER:-new-api}"
SWITCHER_CONTAINER="${SWITCHER_CONTAINER:-cline-pass-switcher}"
SWITCHER_URL="${SWITCHER_URL:-http://cline-pass-switcher:3123}"
DIRECT_URL="${DIRECT_URL:-https://api.cline.bot/api}"
CONFIG_JSON="${CONFIG_JSON:-/mnt/appdata/ChatStack/cline-pass-switcher/data/config.json}"
WAIT=600
MODE=cutover

while [ $# -gt 0 ]; do
  case "$1" in
    --wait) WAIT="$2"; shift 2 ;;
    --rollback) MODE=rollback; shift ;;
    --status) MODE=status; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }
psql_q() { docker exec -i "$PG_CONTAINER" psql -U postgres -d "$PG_DB" -Atq -v ON_ERROR_STOP=1 "$@"; }
channel_url() { psql_q -c "select base_url from channels where id=${CHANNEL_ID}"; }

# Update base_url + key via stdin so the key never shows up in `ps` or docker's exec args.
set_channel() { # $1 = base_url, $2 = key
  printf "update channels set base_url=%s, key=%s where id=%s;\n" \
    "$(printf %s "$1" | sed "s/'/''/g; s/^/'/; s/$/'/")" \
    "$(printf %s "$2" | sed "s/'/''/g; s/^/'/; s/$/'/")" \
    "$CHANNEL_ID" | psql_q >/dev/null
}

if [ "$MODE" = status ]; then
  echo "channel ${CHANNEL_ID} base_url: $(channel_url)"
  exit 0
fi

[ -r "$CONFIG_JSON" ] || { echo "cannot read $CONFIG_JSON" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

if [ "$MODE" = rollback ]; then
  KEY="$(jq -r '.accounts[0].key // empty' "$CONFIG_JSON")"
  [ -n "$KEY" ] || { echo "no accounts[0].key in $CONFIG_JSON" >&2; exit 1; }
  set_channel "$DIRECT_URL" "$KEY"
  log "channel ${CHANNEL_ID} restored to ${DIRECT_URL} (direct Cline Pass key)"
  exit 0
fi

PROXY_KEY="$(jq -r '.proxyKey // empty' "$CONFIG_JSON")"
[ -n "$PROXY_KEY" ] || { echo "proxyKey is empty in $CONFIG_JSON; set one before exposing the proxy" >&2; exit 1; }

# Wait until the switcher is up AND reachable from inside the new-api container (same compose network).
log "waiting up to ${WAIT}s for ${SWITCHER_CONTAINER} to be reachable from ${NEWAPI_CONTAINER} ..."
deadline=$(( $(date +%s) + WAIT ))
until docker exec "$NEWAPI_CONTAINER" wget -q -T 5 -O - "${SWITCHER_URL}/api/meta" 2>/dev/null | grep -q '"configured":true'; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    log "timeout: ${SWITCHER_URL} not reachable from ${NEWAPI_CONTAINER}; channel left unchanged ($(channel_url))"
    exit 1
  fi
  sleep 10
done
log "switcher reachable from ${NEWAPI_CONTAINER}"

# Verify the proxy key is accepted before pointing live traffic at it.
if ! docker exec "$NEWAPI_CONTAINER" wget -q -T 10 -O - --header="Authorization: Bearer ${PROXY_KEY}" \
     "${SWITCHER_URL}/v1/models" 2>/dev/null | grep -q '"cline-pass/'; then
  log "switcher rejected the proxyKey from ${CONFIG_JSON} or returned no cline-pass models; channel left unchanged"
  exit 1
fi

if [ "$(channel_url)" = "$SWITCHER_URL" ]; then
  log "channel ${CHANNEL_ID} already points at ${SWITCHER_URL}; refreshing key only"
fi
set_channel "$SWITCHER_URL" "$PROXY_KEY"
log "channel ${CHANNEL_ID} now -> $(channel_url) (key = switcher proxyKey)"
log "verify: tail new-api logs for channel_id=${CHANNEL_ID}, or open the switcher console and check 请求历史"
