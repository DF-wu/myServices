#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/validate-homepage-template.sh
./scripts/scan-secrets.sh
./scripts/check-homepage-labels.sh
./scripts/render-phase2-summary.py > inventory/private/phase2-private-summary.md

echo "All Homepage Phase 1 checks passed."
