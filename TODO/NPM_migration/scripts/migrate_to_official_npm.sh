#!/usr/bin/env bash
set -euo pipefail

EXECUTE=false
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

SRC_CONFIG_DIR="${SRC_CONFIG_DIR:-/mnt/appdata/NginxProxyManager}"
WORK_ROOT="${WORK_ROOT:-/mnt/appdata/NginxProxyManager_migration}"
TARGET_ROOT="${TARGET_ROOT:-/mnt/appdata/NginxProxyManager_official}"

HOST_HTTP_PORT="${HOST_HTTP_PORT:-18080}"
HOST_HTTPS_PORT="${HOST_HTTPS_PORT:-18443}"
HOST_ADMIN_PORT="${HOST_ADMIN_PORT:-7818}"

OFFICIAL_IMAGE="${OFFICIAL_IMAGE:-docker.io/jc21/nginx-proxy-manager:2.15.1}"
TARGET_CONTAINER_NAME="${TARGET_CONTAINER_NAME:-npm_official}"
TZ_VALUE="${TZ_VALUE:-Asia/Taipei}"

BACKUP_DIR="${WORK_ROOT}/backups/${TIMESTAMP}"
GENERATED_DIR="${WORK_ROOT}/generated/${TIMESTAMP}"
COMPOSE_FILE="${GENERATED_DIR}/docker-compose.official.yml"

log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date +'%F %T')" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$(date +'%F %T')" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  migrate_to_official_npm.sh [--execute]

Default behavior:
  Dry-run only. Reads source inventory and generates compose artifacts.

Execute behavior:
  Stages a new official-NPM data tree and compose artifact.
  It does NOT stop the legacy app and does NOT start the new container.

Environment overrides:
  SRC_CONFIG_DIR      default: /mnt/appdata/NginxProxyManager
  WORK_ROOT           default: /mnt/appdata/NginxProxyManager_migration
  TARGET_ROOT         default: /mnt/appdata/NginxProxyManager_official
  HOST_HTTP_PORT      default: 18080
  HOST_HTTPS_PORT     default: 18443
  HOST_ADMIN_PORT     default: 7818
  OFFICIAL_IMAGE      default: docker.io/jc21/nginx-proxy-manager:2.15.1
  TARGET_CONTAINER_NAME
  ALLOW_OVERWRITE_TARGET=1   required when TARGET_ROOT already has content

Cutover is intentionally manual:
  1. Review generated compose.
  2. Stop/disable the old TrueNAS app through the chosen authority.
  3. Run docker compose -f <generated compose> up -d.
EOF
}

while (($#)); do
  case "$1" in
    --execute) EXECUTE=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

canonical() {
  realpath -m "$1"
}

sqlite_ro() {
  sqlite3 -readonly "$SRC_CONFIG_DIR/database.sqlite" "$1"
}

assert_safe_paths() {
  local src_abs work_abs target_abs
  src_abs="$(canonical "$SRC_CONFIG_DIR")"
  work_abs="$(canonical "$WORK_ROOT")"
  target_abs="$(canonical "$TARGET_ROOT")"

  case "$target_abs" in
    "/"|"/mnt"|"/mnt/appdata"|"/mnt/cachePool"|"/mnt/cachePool/appdata")
      die "TARGET_ROOT is too broad: $TARGET_ROOT"
      ;;
  esac

  if [[ "$target_abs" == "$src_abs" || "$target_abs" == "$src_abs/"* ]]; then
    die "TARGET_ROOT must not be the source tree: $TARGET_ROOT"
  fi

  if [[ "$work_abs" == "$src_abs" || "$work_abs" == "$src_abs/"* ]]; then
    die "WORK_ROOT must not be inside the source tree: $WORK_ROOT"
  fi
}

count_active() {
  local table="$1"
  sqlite_ro "select count(*) from ${table} where is_deleted = 0 and enabled = 1;"
}

stream_port_lines() {
  sqlite_ro "select distinct incoming_port, tcp_forwarding, udp_forwarding from stream where is_deleted = 0 and enabled = 1 order by incoming_port;" \
    | while IFS='|' read -r port tcp udp; do
        [[ -n "$port" ]] || continue
        if [[ "$tcp" == "1" ]]; then
          printf "      - '%s:%s/tcp'\n" "$port" "$port"
        fi
        if [[ "$udp" == "1" ]]; then
          printf "      - '%s:%s/udp'\n" "$port" "$port"
        fi
      done
}

preflight() {
  log "Running preflight checks..."
  require_cmd rsync
  require_cmd sqlite3
  require_cmd tar
  require_cmd awk
  require_cmd grep
  require_cmd sed
  require_cmd find
  require_cmd realpath

  [[ -d "$SRC_CONFIG_DIR" ]] || die "Source config dir not found: $SRC_CONFIG_DIR"
  [[ -f "$SRC_CONFIG_DIR/database.sqlite" ]] || die "Missing source DB: $SRC_CONFIG_DIR/database.sqlite"
  [[ -d "$SRC_CONFIG_DIR/letsencrypt" ]] || die "Missing source letsencrypt dir: $SRC_CONFIG_DIR/letsencrypt"

  assert_safe_paths
  mkdir -p "$GENERATED_DIR"

  local migrations_lock knex_lock
  migrations_lock="$(sqlite_ro "select is_locked from migrations_lock limit 1;" 2>/dev/null || printf 'unknown')"
  knex_lock="$(sqlite_ro "select is_locked from knex_migrations_lock limit 1;" 2>/dev/null || printf 'unknown')"
  [[ "$migrations_lock" == "0" ]] || die "migrations_lock is not clear: $migrations_lock"
  [[ "$knex_lock" == "0" ]] || die "knex_migrations_lock is not clear: $knex_lock"

  local access_missing
  access_missing="$(sqlite_ro "select distinct access_list_id from proxy_host where is_deleted = 0 and enabled = 1 and access_list_id != 0;" \
    | while read -r id; do
        [[ -f "$SRC_CONFIG_DIR/access/$id" ]] || printf '%s\n' "$id"
      done)"
  [[ -z "$access_missing" ]] || die "Missing access htpasswd file(s): $access_missing"

  log "Inventory: proxy=$(count_active proxy_host), redirection=$(count_active redirection_host), dead=$(count_active dead_host), stream=$(count_active stream)"
}

backup_source() {
  log "Creating migration-input snapshot: $BACKUP_DIR/source_config_snapshot.tar.gz"
  mkdir -p "$BACKUP_DIR"

  local snapshot_root="$BACKUP_DIR/source_config_snapshot"
  mkdir -p "$snapshot_root"

  snapshot_path() {
    local rel="$1"
    local src="$SRC_CONFIG_DIR/$rel"
    local dest="$snapshot_root/$rel"

    [[ -e "$src" || -L "$src" ]] || return 0
    mkdir -p "$(dirname "$dest")"

    if [[ -d "$src" && ! -L "$src" ]]; then
      mkdir -p "$dest"
      rsync -a --no-owner --no-group --delete "$src/" "$dest/"
    else
      cp -d --preserve=mode,timestamps "$src" "$dest"
    fi
  }

  snapshot_path database.sqlite
  snapshot_path keys.json
  snapshot_path access
  snapshot_path custom_ssl
  snapshot_path letsencrypt

  for dir in default_host default_www proxy_host redirection_host dead_host stream custom; do
    snapshot_path "nginx/$dir"
  done

  snapshot_path nginx/dummycert.pem
  snapshot_path nginx/dummykey.pem

  tar -C "$BACKUP_DIR" -czf "$BACKUP_DIR/source_config_snapshot.tar.gz" "source_config_snapshot"
}

reset_target() {
  if [[ -d "$TARGET_ROOT" ]] && [[ "$(find "$TARGET_ROOT" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)" -gt 0 ]]; then
    [[ "${ALLOW_OVERWRITE_TARGET:-}" == "1" ]] || die "TARGET_ROOT already has content. Set ALLOW_OVERWRITE_TARGET=1 to replace staged data: $TARGET_ROOT"
  fi

  rm -rf "$TARGET_ROOT/data" "$TARGET_ROOT/letsencrypt"
  mkdir -p \
    "$TARGET_ROOT/data" \
    "$TARGET_ROOT/data/nginx" \
    "$TARGET_ROOT/data/nginx/default_host" \
    "$TARGET_ROOT/data/nginx/default_www" \
    "$TARGET_ROOT/data/nginx/proxy_host" \
    "$TARGET_ROOT/data/nginx/redirection_host" \
    "$TARGET_ROOT/data/nginx/dead_host" \
    "$TARGET_ROOT/data/nginx/stream" \
    "$TARGET_ROOT/data/nginx/custom" \
    "$TARGET_ROOT/data/logs" \
    "$TARGET_ROOT/data/access" \
    "$TARGET_ROOT/letsencrypt"
}

copy_core_assets() {
  log "Copying core assets into official layout..."
  # Consistent snapshot via SQLite online-backup API instead of cp: safe even if the
  # source NPM is live, and never writes to the source (opened read-only).
  sqlite3 -readonly "$SRC_CONFIG_DIR/database.sqlite" ".backup '$TARGET_ROOT/data/database.sqlite'"
  [[ ! -f "$SRC_CONFIG_DIR/keys.json" ]] || cp -d --preserve=mode,timestamps "$SRC_CONFIG_DIR/keys.json" "$TARGET_ROOT/data/keys.json"
  [[ ! -d "$SRC_CONFIG_DIR/access" ]] || rsync -a --no-owner --no-group --delete "$SRC_CONFIG_DIR/access/" "$TARGET_ROOT/data/access/"
  [[ ! -d "$SRC_CONFIG_DIR/custom_ssl" ]] || rsync -a --no-owner --no-group --delete "$SRC_CONFIG_DIR/custom_ssl/" "$TARGET_ROOT/data/custom_ssl/"
  rsync -a --no-owner --no-group --delete "$SRC_CONFIG_DIR/letsencrypt/" "$TARGET_ROOT/letsencrypt/"
}

copy_bootstrap_nginx() {
  log "Copying and sanitizing bootstrap nginx configs..."

  for dir in default_host default_www proxy_host redirection_host dead_host stream custom; do
    if [[ -d "$SRC_CONFIG_DIR/nginx/$dir" ]]; then
      rsync -a --no-owner --no-group --delete "$SRC_CONFIG_DIR/nginx/$dir/" "$TARGET_ROOT/data/nginx/$dir/"
    fi
  done

  for file in dummycert.pem dummykey.pem; do
    [[ ! -f "$SRC_CONFIG_DIR/nginx/$file" ]] || cp -d --preserve=mode,timestamps "$SRC_CONFIG_DIR/nginx/$file" "$TARGET_ROOT/data/nginx/$file"
  done

  find "$TARGET_ROOT/data/nginx" -type f -name '*.conf' -print0 | while IFS= read -r -d '' file; do
    sed -i \
      -e 's|/config/log/|/data/logs/|g' \
      -e 's|/config/log|/data/logs|g' \
      -e 's|listen 8080|listen 80|g' \
      -e 's|listen \[::\]:8080|listen [::]:80|g' \
      -e 's|listen 4443|listen 443|g' \
      -e 's|listen \[::\]:4443|listen [::]:443|g' \
      "$file"
  done

  if grep -R -n '/config/' "$TARGET_ROOT/data/nginx" >/dev/null 2>&1; then
    grep -R -n '/config/' "$TARGET_ROOT/data/nginx" >&2 || true
    die "Sanitized nginx configs still contain /config paths"
  fi

  if grep -R -nE 'listen (8080|4443)' "$TARGET_ROOT/data/nginx" >/dev/null 2>&1; then
    grep -R -nE 'listen (8080|4443)' "$TARGET_ROOT/data/nginx" >&2 || true
    die "Sanitized nginx configs still contain jlesage listen ports"
  fi
}

normalize_permissions() {
  log "Normalizing sensitive file permissions..."
  chmod 700 "$TARGET_ROOT/data" "$TARGET_ROOT/letsencrypt" || true
  chmod 600 "$TARGET_ROOT/data/database.sqlite" || true
  [[ ! -f "$TARGET_ROOT/data/keys.json" ]] || chmod 600 "$TARGET_ROOT/data/keys.json" || true
  find "$TARGET_ROOT/data/access" -type f -exec chmod 600 {} + 2>/dev/null || true
  find "$TARGET_ROOT/letsencrypt/credentials" -type f -exec chmod 600 {} + 2>/dev/null || true
  find "$TARGET_ROOT/letsencrypt/archive" -type f -name 'privkey*.pem' -exec chmod 600 {} + 2>/dev/null || true
}

generate_compose() {
  log "Generating compose artifact: $COMPOSE_FILE"
  local stream_ports
  stream_ports="$(stream_port_lines)"

  cat > "$COMPOSE_FILE" <<EOF
services:
  npm_official:
    image: '${OFFICIAL_IMAGE}'
    container_name: ${TARGET_CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - '${HOST_HTTP_PORT}:80/tcp'
      - '${HOST_HTTPS_PORT}:443/tcp'
      - '${HOST_ADMIN_PORT}:81/tcp'
${stream_ports}
    environment:
      TZ: '${TZ_VALUE}'
      DISABLE_IPV6: 'true'
    volumes:
      - '${TARGET_ROOT}/data:/data'
      - '${TARGET_ROOT}/letsencrypt:/etc/letsencrypt'
    healthcheck:
      test: ["CMD", "/usr/bin/check-health"]
      interval: 10s
      timeout: 3s
EOF
}

validate_compose_if_possible() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" config >/dev/null
    log "docker compose config passed"
  else
    warn "docker compose not available; skipped compose validation"
  fi
}

prepare_target_data() {
  backup_source
  reset_target
  copy_core_assets
  copy_bootstrap_nginx
  normalize_permissions
}

main() {
  preflight
  generate_compose
  validate_compose_if_possible

  if [[ "$EXECUTE" == "true" ]]; then
    prepare_target_data
    log "Staging complete. No containers were stopped or started."
  else
    log "Dry-run complete. No production data was copied."
  fi

  log "Compose artifact: $COMPOSE_FILE"
  log "Target root: $TARGET_ROOT"
  log "Backup directory: $BACKUP_DIR"
}

main
