#!/usr/bin/env bash
set -euo pipefail

echo "== Homepage label audit =="
found=0
bad=0
while IFS= read -r c; do
  labels="$(docker inspect "$c" --format '{{json .Config.Labels}}' 2>/dev/null || echo '{}')"
  if printf '%s' "$labels" | grep -q 'homepage\.'; then
    found=$((found + 1))
    echo "-- $c"
    printf '%s' "$labels" | jq -r 'to_entries[] | select(.key|startswith("homepage.")) | "\(.key)=\(.value)"'
    if printf '%s' "$labels" | jq -r 'to_entries[] | select(.key|startswith("homepage.")) | "\(.key)=\(.value)"' | grep -Eiq '(password|token|api[_-]?key|secret|bearer|sk-[A-Za-z0-9_-]{12,})'; then
      echo "Potential secret-looking Homepage label on $c" >&2
      bad=$((bad + 1))
    fi
  fi
done < <(docker ps --format '{{.Names}}' | sort)

echo "Homepage-labeled containers: $found"
if [ "$bad" -gt 0 ]; then
  exit 1
fi
