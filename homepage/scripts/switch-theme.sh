#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET_ROOT="${HOMEPAGE_THEME_PRESET_DIR:-${ROOT_DIR}/config-template/themes}"
CONFIG_DIR="${HOMEPAGE_CONFIG_DIR:-/mnt/appdata/homepage/config}"
BACKUP_DIR="${HOMEPAGE_THEME_BACKUP_DIR:-${CONFIG_DIR}/.theme-backups}"
RESTART=1
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/switch-theme.sh list
  ./scripts/switch-theme.sh current
  ./scripts/switch-theme.sh history
  ./scripts/switch-theme.sh <preset> [--dry-run] [--no-restart]
  ./scripts/switch-theme.sh rollback [backup-id] [--dry-run] [--no-restart]

Options:
  --dry-run              Render and validate without changing runtime files.
  --no-restart           Apply files but leave reload to a maintenance window.
  --config-dir DIR       Override the Homepage runtime config directory.
  --backup-dir DIR       Override the theme backup directory.
EOF
}

die() {
  printf 'switch-theme: %s\n' "$*" >&2
  exit 1
}

get_kv() {
  local file="$1" key="$2"
  awk -F= -v wanted="$key" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' "$file"
}

manifest_line() {
  local wanted="$1"
  awk -F'|' -v wanted="$wanted" '$1 == wanted {print; exit}' "$PRESET_ROOT/index.tsv"
}

preset_name() {
  local line
  line="$(manifest_line "$1")"
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line" | awk -F'|' '{print $2}'
  else
    printf '%s\n' "$1"
  fi
}

current_preset() {
  local css_file="$CONFIG_DIR/custom.css"
  local marker=''
  if [[ -f "$css_file" ]]; then
    marker="$(sed -n '1s@^/\* Homepage theme preset: \([^*]*\) \*/.*$@\1@p' "$css_file")"
    if [[ -n "$marker" ]]; then
      printf '%s\n' "$marker"
      return 0
    fi
    if [[ -f "$PRESET_ROOT/dracula/custom.css" ]] && cmp -s "$css_file" "$PRESET_ROOT/dracula/custom.css"; then
      printf 'dracula\n'
      return 0
    fi
  fi
  printf 'custom\n'
}

print_presets() {
  local current id name description marker
  current="$(current_preset 2>/dev/null || printf 'custom')"
  printf '%-16s %-20s %s\n' 'ID' 'NAME' 'DESCRIPTION'
  printf '%-16s %-20s %s\n' '----------------' '--------------------' '------------------------------'
  while IFS='|' read -r id name description; do
    [[ -z "${id:-}" || "${id:0:1}" == '#' ]] && continue
    [[ -d "$PRESET_ROOT/$id" ]] || continue
    marker=' '
    [[ "$id" == "$current" ]] && marker='*'
    printf '%s%-15s %-20s %s\n' "$marker" "$id" "$name" "$description"
  done < "$PRESET_ROOT/index.tsv"
  printf '\n* active or matching preset (list never changes runtime files)\n'
}

validate_preset() {
  local id="$1" dir="$PRESET_ROOT/$1" required value
  [[ "$id" =~ ^[a-z0-9-]+$ ]] || die "invalid preset id: $id"
  [[ -d "$dir" ]] || die "unknown preset: $id (run '$0 list')"
  [[ -f "$dir/preset.conf" ]] || die "missing preset.conf for $id"
  for required in theme color headerStyle statusStyle iconStyle cardBlur fullWidth maxGroupColumns maxBookmarkGroupColumns background css; do
    value="$(get_kv "$dir/preset.conf" "$required")"
    [[ -n "$value" ]] || die "missing $required in $dir/preset.conf"
  done
  case "$(get_kv "$dir/preset.conf" theme)" in dark|light) ;; *) die "theme must be dark or light for $id" ;; esac
  case "$(get_kv "$dir/preset.conf" color)" in
    white|slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose) ;;
    *) die "unsupported Homepage color for $id" ;;
  esac
  case "$(get_kv "$dir/preset.conf" headerStyle)" in clean|boxedWidgets|underlined|boxed) ;; *) die "invalid headerStyle for $id" ;; esac
  case "$(get_kv "$dir/preset.conf" statusStyle)" in dot|basic) ;; *) die "invalid statusStyle for $id" ;; esac
  case "$(get_kv "$dir/preset.conf" iconStyle)" in theme) ;; *) die "invalid iconStyle for $id" ;; esac
  case "$(get_kv "$dir/preset.conf" cardBlur)" in true|false|omit) ;; *) die "invalid cardBlur for $id" ;; esac
  case "$(get_kv "$dir/preset.conf" fullWidth)" in true|false) ;; *) die "invalid fullWidth for $id" ;; esac
  [[ "$(get_kv "$dir/preset.conf" maxGroupColumns)" =~ ^[1-9][0-9]*$ ]] || die "invalid maxGroupColumns for $id"
  [[ "$(get_kv "$dir/preset.conf" maxBookmarkGroupColumns)" =~ ^[1-9][0-9]*$ ]] || die "invalid maxBookmarkGroupColumns for $id"
  case "$(get_kv "$dir/preset.conf" css)" in
    base) [[ -f "$PRESET_ROOT/_base.css" && -f "$dir/theme.css" ]] || die "base CSS files missing for $id" ;;
    dracula) [[ -f "$dir/custom.css" ]] || die "Dracula CSS missing" ;;
    *) die "unknown css mode for $id" ;;
  esac
  case "$(get_kv "$dir/preset.conf" background)" in
    none) ;;
    image) [[ -n "$(get_kv "$dir/preset.conf" backgroundImage)" ]] || die "backgroundImage missing for $id" ;;
    *) die "unknown background mode for $id" ;;
  esac
}

render_settings() {
  local source="$1" conf="$2" output="$3"
  python3 - "$source" "$conf" "$output" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"PyYAML is required to render a theme: {exc}")

source, conf_path, output = map(Path, sys.argv[1:])
conf = {}
for raw in conf_path.read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    key, sep, value = line.partition("=")
    if sep:
        conf[key.strip()] = value.strip()

settings = yaml.safe_load(source.read_text())
if not isinstance(settings, dict):
    raise SystemExit(f"{source} must contain a YAML mapping")

settings["theme"] = conf["theme"]
settings["color"] = conf["color"]
settings["headerStyle"] = conf["headerStyle"]
settings["statusStyle"] = conf["statusStyle"]
settings["iconStyle"] = conf["iconStyle"]
settings["fullWidth"] = conf["fullWidth"] == "true"
settings["maxGroupColumns"] = int(conf["maxGroupColumns"])
settings["maxBookmarkGroupColumns"] = int(conf["maxBookmarkGroupColumns"])

if conf["cardBlur"] == "omit":
    settings.pop("cardBlur", None)
else:
    settings["cardBlur"] = conf["cardBlur"] == "true"

if conf["background"] == "none":
    settings.pop("background", None)
else:
    settings["background"] = {
        "image": conf["backgroundImage"],
        "blur": conf.get("backgroundBlur", "sm"),
        "saturate": int(conf.get("backgroundSaturate", "50")),
        "brightness": int(conf.get("backgroundBrightness", "50")),
        "opacity": int(conf.get("backgroundOpacity", "50")),
    }

output.write_text(yaml.safe_dump(settings, allow_unicode=True, sort_keys=False, width=120, explicit_start=True))
PY
}

render_css() {
  local id="$1" output="$2" dir="$PRESET_ROOT/$1"
  case "$(get_kv "$dir/preset.conf" css)" in
    dracula) cp "$dir/custom.css" "$output" ;;
    base)
      {
        printf '/* Homepage theme preset: %s */\n' "$id"
        cat "$PRESET_ROOT/_base.css"
        printf '\n'
        cat "$dir/theme.css"
        printf '\n'
      } > "$output"
      ;;
  esac
}

validate_yaml() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys
from pathlib import Path
try:
    import yaml
except Exception as exc:
    raise SystemExit(f"PyYAML is required for validation: {exc}")
path = Path(sys.argv[1])
with path.open() as handle:
    value = yaml.safe_load(handle)
if not isinstance(value, dict):
    raise SystemExit(f"{path} must contain a YAML mapping")
PY
}

backup_current() {
  local id stamp safe_id destination
  mkdir -p "$BACKUP_DIR"
  id="$(current_preset)"
  safe_id="${id//[^a-zA-Z0-9._-]/custom}"
  stamp="$(date +%Y%m%d-%H%M%S)-$$"
  destination="$BACKUP_DIR/${stamp}-${safe_id}"
  mkdir -p "$destination"
  cp -p "$CONFIG_DIR/settings.yaml" "$destination/settings.yaml"
  cp -p "$CONFIG_DIR/custom.css" "$destination/custom.css"
  printf '%s\n' "$id" > "$destination/preset.id"
  printf '%s\n' "$destination"
}

copy_in_place() {
  local source="$1" destination="$2"
  # Keep the existing inode owner/mode (the container owns these files as UID 3000).
  cat "$source" > "$destination"
}

restore_backup() {
  local source="$1"
  copy_in_place "$source/settings.yaml" "$CONFIG_DIR/settings.yaml"
  copy_in_place "$source/custom.css" "$CONFIG_DIR/custom.css"
}

runtime_port() {
  if [[ -n "${HOMEPAGE_HOST_PORT:-}" ]]; then
    printf '%s\n' "$HOMEPAGE_HOST_PORT"
    return
  fi
  if [[ -f "$ROOT_DIR/.env" ]]; then
    local from_env
    from_env="$(get_kv "$ROOT_DIR/.env" HOMEPAGE_HOST_PORT)"
    [[ -n "$from_env" ]] && printf '%s\n' "$from_env" && return
  fi
  printf '33080\n'
}

restart_and_check() {
  local running
  running="$(docker inspect --format '{{.State.Running}}' homepage 2>/dev/null || true)"
  if [[ "$running" == "true" ]]; then
    # Homepage serves a long-lived ISR page (en.html/en.json). Remove only
    # generated page artifacts so settings such as background/headerStyle take
    # effect immediately after the restart; API routes and the compiled build
    # remain untouched.
    docker exec homepage sh -c 'rm -f /app/.next/server/pages/*.html /app/.next/server/pages/*.json'
  fi
  docker compose restart homepage
  local url="http://127.0.0.1:$(runtime_port)/" attempt
  for attempt in $(seq 1 30); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  printf 'Homepage did not respond at %s after restart.\n' "$url" >&2
  return 1
}

apply_preset() {
  local id="$1"
  validate_preset "$id"
  [[ -d "$CONFIG_DIR" ]] || die "runtime config directory does not exist: $CONFIG_DIR"
  [[ -f "$CONFIG_DIR/settings.yaml" ]] || die "missing runtime settings.yaml in $CONFIG_DIR"
  [[ -f "$CONFIG_DIR/custom.css" ]] || die "missing runtime custom.css in $CONFIG_DIR"
  [[ -w "$CONFIG_DIR/settings.yaml" && -w "$CONFIG_DIR/custom.css" ]] || die "runtime theme files are not writable: $CONFIG_DIR"

  local workdir settings_tmp css_tmp backup
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/homepage-theme.XXXXXX")"
  trap 'rm -rf "$workdir"' RETURN
  settings_tmp="$workdir/settings.yaml"
  css_tmp="$workdir/custom.css"
  render_settings "$CONFIG_DIR/settings.yaml" "$PRESET_ROOT/$id/preset.conf" "$settings_tmp"
  render_css "$id" "$css_tmp"
  validate_yaml "$settings_tmp"
  [[ -s "$css_tmp" ]] || die "generated custom.css is empty"

  printf 'Preset: %s (%s)\n' "$id" "$(preset_name "$id")"
  printf 'Runtime: %s\n' "$CONFIG_DIR"
  printf 'Settings: %s -> %s\n' "$(sha256sum "$CONFIG_DIR/settings.yaml" | awk '{print $1}')" "$(sha256sum "$settings_tmp" | awk '{print $1}')"
  printf 'CSS:      %s -> %s\n' "$(sha256sum "$CONFIG_DIR/custom.css" | awk '{print $1}')" "$(sha256sum "$css_tmp" | awk '{print $1}')"

  if cmp -s "$CONFIG_DIR/settings.yaml" "$settings_tmp" && cmp -s "$CONFIG_DIR/custom.css" "$css_tmp"; then
    printf 'Already active; no files changed and no restart requested.\n'
    return 0
  fi

  if (( DRY_RUN )); then
    printf '\nDry run only; no files changed and no restart requested.\n'
    diff -u "$CONFIG_DIR/settings.yaml" "$settings_tmp" | sed -n '1,180p' || true
    return 0
  fi

  backup="$(backup_current)"
  if ! copy_in_place "$settings_tmp" "$CONFIG_DIR/settings.yaml" || ! copy_in_place "$css_tmp" "$CONFIG_DIR/custom.css"; then
    restore_backup "$backup"
    die "failed to write theme files; restored backup $backup"
  fi

  if (( RESTART )); then
    if ! restart_and_check; then
      restore_backup "$backup"
      restart_and_check || true
      die "restart/health check failed; restored backup $backup"
    fi
    printf 'Applied and healthy. Backup: %s\n' "$backup"
  else
    printf 'Applied without restart. Backup: %s\n' "$backup"
    printf 'Run: docker compose restart homepage\n'
  fi
}

rollback() {
  local requested="$1" target current_backup
  if [[ -n "$requested" ]]; then
    target="$BACKUP_DIR/$requested"
  else
    target="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1 || true)"
  fi
  [[ -n "$target" && -d "$target" ]] || die "no theme backup found in $BACKUP_DIR"
  [[ -f "$target/settings.yaml" && -f "$target/custom.css" ]] || die "incomplete theme backup: $target"

  printf 'Rollback target: %s\n' "$(basename "$target")"
  if (( DRY_RUN )); then
    printf 'Dry run only; no files changed and no restart requested.\n'
    return 0
  fi

  current_backup="$(backup_current)"
  if ! restore_backup "$target"; then
    restore_backup "$current_backup"
    die "rollback failed; restored current files from $current_backup"
  fi
  if (( RESTART )); then
    if ! restart_and_check; then
      restore_backup "$current_backup"
      restart_and_check || true
      die "rollback health check failed; restored current files from $current_backup"
    fi
  fi
  printf 'Rollback applied. Previous files backed up at: %s\n' "$current_backup"
}

print_history() {
  [[ -d "$BACKUP_DIR" ]] || { printf 'No theme backups yet (%s).\n' "$BACKUP_DIR"; return; }
  local dir id
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    id='unknown'
    [[ -f "$dir/preset.id" ]] && id="$(sed -n '1p' "$dir/preset.id")"
    printf '%s\t%s\n' "$(basename "$dir")" "$id"
  done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-restart) RESTART=0; shift ;;
    --config-dir)
      [[ $# -ge 2 ]] || die "--config-dir needs a value"
      CONFIG_DIR="$2"
      shift 2
      ;;
    --backup-dir)
      [[ $# -ge 2 ]] || die "--backup-dir needs a value"
      BACKUP_DIR="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; POSITIONAL+=("$@"); break ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

COMMAND="${POSITIONAL[0]:-list}"
ARGUMENT="${POSITIONAL[1]:-}"
[[ ${#POSITIONAL[@]} -le 2 ]] || die "too many arguments"

case "$COMMAND" in
  list)
    [[ -f "$PRESET_ROOT/index.tsv" ]] || die "missing preset index: $PRESET_ROOT/index.tsv"
    print_presets
    ;;
  current)
    printf 'Current preset: %s\n' "$(current_preset)"
    printf 'Runtime config: %s\n' "$CONFIG_DIR"
    ;;
  history)
    print_history
    ;;
  rollback)
    rollback "$ARGUMENT"
    ;;
  *)
    [[ -z "$ARGUMENT" ]] || die "unexpected argument: $ARGUMENT"
    apply_preset "$COMMAND"
    ;;
esac
