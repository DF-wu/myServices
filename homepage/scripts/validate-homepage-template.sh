#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

WORK_DIR="$(mktemp -d /tmp/homepage-template-validation.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "== docker compose render =="
docker compose --env-file config-template/.env.example -f config-template/docker-compose.yml config >"$WORK_DIR/compose.yml"
docker compose --env-file config-template/.env.example -f config-template/docker-compose.yml config --services
cmp docker-compose.yml config-template/docker-compose.yml

echo "== Portainer Git checkout render =="
PORTAINER_CHECKOUT="$WORK_DIR/portainer-checkout"
mkdir -p "$PORTAINER_CHECKOUT/homepage"
cp docker-compose.yml "$PORTAINER_CHECKOUT/homepage/docker-compose.yml"
cp config-template/.env.example "$PORTAINER_CHECKOUT/stack.env"
docker compose \
  --env-file "$PORTAINER_CHECKOUT/stack.env" \
  -f "$PORTAINER_CHECKOUT/homepage/docker-compose.yml" \
  config --services

echo "== YAML parse check =="
python - <<'PY'
from pathlib import Path
try:
    import yaml
except Exception as e:
    raise SystemExit(f"PyYAML not available: {e}")
for p in sorted(Path('config-template/config').glob('*.yaml')):
    with p.open() as f:
        yaml.safe_load(f)
    print(f"ok {p}")
PY

echo "== theme preset check =="
bash -n scripts/switch-theme.sh
PYTHONPYCACHEPREFIX="$WORK_DIR/pycache" \
  python3 -m py_compile scripts/apply-theme-preset.py scripts/validate-theme-presets.py
python3 scripts/validate-theme-presets.py
THEME_TEST_DIR="$WORK_DIR/theme"
while IFS='|' read -r preset_id _; do
  [ -z "${preset_id:-}" ] && continue
  case "$preset_id" in \#*) continue ;; esac
  rm -rf "$THEME_TEST_DIR"
  mkdir -p "$THEME_TEST_DIR"
  cp config-template/config/settings.yaml "$THEME_TEST_DIR/settings.yaml"
  cp config-template/config/custom.css "$THEME_TEST_DIR/custom.css"
  before_layout="$(python3 - "$THEME_TEST_DIR/settings.yaml" <<'PY'
import sys
import yaml
with open(sys.argv[1]) as handle:
    print(yaml.safe_dump(yaml.safe_load(handle).get("layout"), sort_keys=True))
PY
)"
  python3 scripts/apply-theme-preset.py "$preset_id" \
    --config-dir "$THEME_TEST_DIR" \
    --preset-dir config-template/themes >/dev/null
  after_layout="$(python3 - "$THEME_TEST_DIR/settings.yaml" <<'PY'
import sys
import yaml
with open(sys.argv[1]) as handle:
    print(yaml.safe_dump(yaml.safe_load(handle).get("layout"), sort_keys=True))
PY
)"
  [ "$before_layout" = "$after_layout" ]
  cp config-template/config/settings.yaml "$THEME_TEST_DIR/settings.yaml"
  cp config-template/config/custom.css "$THEME_TEST_DIR/custom.css"
  ./scripts/switch-theme.sh "$preset_id" \
    --config-dir "$THEME_TEST_DIR" \
    --backup-dir "$THEME_TEST_DIR/backups" \
    --dry-run >/dev/null
  echo "ok theme $preset_id"
done < config-template/themes/index.tsv
