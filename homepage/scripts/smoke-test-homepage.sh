#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${HOMEPAGE_HOST_PORT:-33000}"
URL="http://127.0.0.1:${PORT}/"

echo "== Compose status =="
docker compose ps || true

echo "== Container presence =="
docker inspect homepage >/dev/null
docker inspect homepage-dockerproxy >/dev/null

echo "== HTTP smoke: $URL =="
for i in $(seq 1 30); do
  if curl -fsS "$URL" >/dev/null; then
    echo "Homepage responded successfully."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "Homepage did not respond after waiting." >&2
    docker logs --tail 200 homepage || true
    exit 1
  fi
  sleep 2
done

echo "== Recent homepage logs =="
docker logs --tail 120 homepage || true

echo "== Recent dockerproxy logs =="
docker logs --tail 80 homepage-dockerproxy || true

echo "Smoke test passed."
