#!/bin/bash
# Clone CRS 和 sub2api repos 用於分析
# 用法: ./05-clone-repos.sh [output_dir]

set -euo pipefail

OUTPUT="${1:-/tmp}"

echo "=== Cloning repositories ==="

if [ ! -d "$OUTPUT/crs" ]; then
    echo "Cloning claude-relay-service..."
    git clone --depth 1 https://github.com/Wei-Shaw/claude-relay-service "$OUTPUT/crs"
else
    echo "CRS already exists at $OUTPUT/crs, pulling latest..."
    git -C "$OUTPUT/crs" pull --ff-only 2>/dev/null || echo "  (pull failed, using existing)"
fi

if [ ! -d "$OUTPUT/sub2api" ]; then
    echo "Cloning sub2api..."
    git clone --depth 1 https://github.com/Wei-Shaw/sub2api "$OUTPUT/sub2api"
else
    echo "sub2api already exists at $OUTPUT/sub2api, pulling latest..."
    git -C "$OUTPUT/sub2api" pull --ff-only 2>/dev/null || echo "  (pull failed, using existing)"
fi

echo ""
echo "=== Repository versions ==="
echo "CRS:     $(git -C "$OUTPUT/crs" log --oneline -1 2>/dev/null || echo 'N/A')"
echo "sub2api: $(git -C "$OUTPUT/sub2api" log --oneline -1 2>/dev/null || echo 'N/A')"
echo ""
echo "Done. Repos at:"
echo "  $OUTPUT/crs"
echo "  $OUTPUT/sub2api"
