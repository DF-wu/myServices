#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== docker compose render =="
cp -f config-template/.env.example config-template/.env
docker compose --env-file config-template/.env.example -f config-template/docker-compose.yml config >/tmp/homepage-compose.rendered.yml
rm -f config-template/.env
sed -n '1,220p' /tmp/homepage-compose.rendered.yml

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
