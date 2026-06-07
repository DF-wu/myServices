#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG_DIR="${HOMEPAGE_CONFIG_DIR:-/mnt/appdata/homepage/config}"

mkdir -p "$CONFIG_DIR"
rsync -av --ignore-existing config-template/config/ "$CONFIG_DIR/"

if [ ! -f .env ]; then
  cp config-template/.env.example .env
  echo "Created .env from config-template/.env.example"
else
  echo ".env already exists; leaving it unchanged"
fi

echo "Runtime config directory: $CONFIG_DIR"
echo "Next steps: edit .env and $CONFIG_DIR/*.yaml before docker compose up -d"
