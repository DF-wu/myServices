#!/bin/bash
# 從 CRS 和 sub2api 中提取所有 OAuth/fingerprint 相關的關鍵原始碼
# 用法: ./06-extract-key-source.sh [crs_path] [sub2api_path] [output_dir]

set -euo pipefail

CRS="${1:-/tmp/crs}"
SUB2API="${2:-/tmp/sub2api}"
OUTPUT="${3:-/tmp/fingerprint-lab/evidence/source}"

mkdir -p "$OUTPUT/crs" "$OUTPUT/sub2api"

echo "=== Extracting key source files ==="

# CRS 關鍵文件
CRS_FILES=(
    "src/utils/oauthHelper.js"
    "src/utils/workosOAuthHelper.js"
    "src/utils/headerFilter.js"
    "src/utils/metadataUserIdHelper.js"
    "src/utils/sessionHelper.js"
    "src/services/claudeCodeHeadersService.js"
    "src/services/requestIdentityService.js"
    "src/services/relay/claudeRelayService.js"
    "src/services/account/claudeAccountService.js"
    "src/validators/clients/claudeCodeValidator.js"
    "src/utils/contents.js"
    ".env.example"
)

echo ""
echo "--- CRS files ---"
for f in "${CRS_FILES[@]}"; do
    src="$CRS/$f"
    dst="$OUTPUT/crs/$(basename "$f")"
    if [ -f "$src" ]; then
        cp "$src" "$dst"
        echo "  ✓ $f → $dst"
    else
        echo "  ✗ $f (not found)"
    fi
done

# sub2api 關鍵文件
SUB2API_FILES=(
    "backend/internal/pkg/oauth/oauth.go"
    "backend/internal/pkg/openai/oauth.go"
    "backend/internal/pkg/geminicli/oauth.go"
    "backend/internal/pkg/geminicli/constants.go"
    "backend/internal/pkg/claude/constants.go"
    "backend/internal/repository/claude_oauth_service.go"
    "backend/internal/repository/openai_oauth_service.go"
    "backend/internal/service/oauth_service.go"
    "backend/internal/service/identity_service.go"
    "backend/internal/service/metadata_userid.go"
    "backend/internal/service/header_util.go"
    "backend/internal/service/gateway_service.go"
    "backend/internal/service/claude_code_validator.go"
    "backend/internal/pkg/tlsfingerprint/dialer.go"
    "backend/internal/model/tls_fingerprint_profile.go"
    "backend/internal/service/token_refresher.go"
    "backend/internal/middleware/rate_limiter.go"
)

echo ""
echo "--- sub2api files ---"
for f in "${SUB2API_FILES[@]}"; do
    src="$SUB2API/$f"
    dst="$OUTPUT/sub2api/$(basename "$f")"
    if [ -f "$src" ]; then
        cp "$src" "$dst"
        echo "  ✓ $f → $dst"
    else
        echo "  ✗ $f (not found)"
    fi
done

echo ""
echo "Done. Key source files at: $OUTPUT/"
echo "CRS files:     $(ls "$OUTPUT/crs/" | wc -l)"
echo "sub2api files: $(ls "$OUTPUT/sub2api/" | wc -l)"
