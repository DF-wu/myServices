#!/bin/bash
# 比較 Claude Code / CRS / sub2api 的指紋差異
# 前提: 已 clone 兩個 repo 到 /tmp/crs 和 /tmp/sub2api
#
# 用法: ./03-compare-fingerprints.sh [crs_path] [sub2api_path]

set -euo pipefail

CRS_PATH="${1:-/tmp/crs}"
SUB2API_PATH="${2:-/tmp/sub2api}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================================"
echo " Fingerprint Comparison: Claude Code vs CRS vs sub2api"
echo "========================================================"
echo ""

# --- 1. Token Endpoint ---
echo "=== 1. Token Endpoint ==="
echo ""

CC_TOKEN_URL="https://platform.claude.com/v1/oauth/token"
echo -e "Claude Code: ${GREEN}${CC_TOKEN_URL}${NC}"

if [ -d "$CRS_PATH" ]; then
    CRS_TOKEN=$(grep -roh 'https://[a-z.]*anthropic\.com[^"]*oauth/token' "$CRS_PATH/src/" 2>/dev/null | sort -u | head -1)
    if [ "$CRS_TOKEN" = "$CC_TOKEN_URL" ]; then
        echo -e "CRS:         ${GREEN}${CRS_TOKEN}${NC} ✓"
    else
        echo -e "CRS:         ${RED}${CRS_TOKEN:-NOT FOUND}${NC} ✗ MISMATCH"
    fi
else
    echo "CRS: repo not found at $CRS_PATH"
fi

if [ -d "$SUB2API_PATH" ]; then
    S2A_TOKEN=$(grep -roh 'https://[a-z.]*claude\.com[^"]*oauth/token\|https://[a-z.]*anthropic\.com[^"]*oauth/token' "$SUB2API_PATH/backend/" 2>/dev/null | sort -u | head -1)
    if [ "$S2A_TOKEN" = "$CC_TOKEN_URL" ]; then
        echo -e "sub2api:     ${GREEN}${S2A_TOKEN}${NC} ✓"
    else
        echo -e "sub2api:     ${RED}${S2A_TOKEN:-NOT FOUND}${NC} ✗ MISMATCH"
    fi
else
    echo "sub2api: repo not found at $SUB2API_PATH"
fi

# --- 2. Token UA ---
echo ""
echo "=== 2. Token Exchange User-Agent ==="
echo ""

echo -e "Claude Code: ${GREEN}axios/<bundled_version> (automatic)${NC}"

if [ -d "$CRS_PATH" ]; then
    CRS_TOKEN_UA=$(grep -rn "User-Agent.*claude-cli" "$CRS_PATH/src/utils/oauthHelper.js" 2>/dev/null | head -1 | grep -oP "'[^']*'" | head -1)
    echo -e "CRS:         ${RED}${CRS_TOKEN_UA:-NOT FOUND}${NC} ✗ WRONG FORMAT (should be axios/*)"
fi

if [ -d "$SUB2API_PATH" ]; then
    S2A_TOKEN_UA=$(grep -n "User-Agent.*axios" "$SUB2API_PATH/backend/internal/repository/claude_oauth_service.go" 2>/dev/null | head -1 | grep -oP '"[^"]*axios[^"]*"' | head -1)
    echo -e "sub2api:     ${GREEN}${S2A_TOKEN_UA:-NOT FOUND}${NC} ✓ Matches Claude Code"
fi

# --- 3. API UA ---
echo ""
echo "=== 3. API Request User-Agent ==="
echo ""

echo "Claude Code: claude-cli/<version> (external, cli) — dynamic, matches installed version"

if [ -d "$CRS_PATH" ]; then
    CRS_API_UA=$(grep -roh "claude-cli/[0-9.]*" "$CRS_PATH/src/services/" 2>/dev/null | sort -u | tail -1)
    echo -e "CRS:         ${YELLOW}${CRS_API_UA:-NOT FOUND}${NC} — check if version is current"
fi

if [ -d "$SUB2API_PATH" ]; then
    S2A_API_UA=$(grep -oP '"User-Agent":\s*"[^"]*"' "$SUB2API_PATH/backend/internal/pkg/claude/constants.go" 2>/dev/null | head -1)
    echo -e "sub2api:     ${YELLOW}${S2A_API_UA:-NOT FOUND}${NC} — check if version is current"
fi

# --- 4. Accept-Encoding ---
echo ""
echo "=== 4. Accept-Encoding ==="
echo ""

echo -e "Claude Code: ${GREEN}gzip, compress, deflate, br${NC} (axios default)"

if [ -d "$CRS_PATH" ]; then
    CRS_AE=$(grep -rn "accept-encoding.*identity\|identity.*accept-encoding" "$CRS_PATH/src/" 2>/dev/null | head -1)
    if [ -n "$CRS_AE" ]; then
        echo -e "CRS:         ${RED}identity (forced)${NC} ✗ DETECTABLE"
    else
        echo "CRS:         not explicitly set"
    fi
fi

echo "sub2api:     depends on Go HTTP client config"

# --- 5. x-stainless-* defaults ---
echo ""
echo "=== 5. X-Stainless Default Headers ==="
echo ""

if [ -d "$CRS_PATH" ]; then
    echo "CRS defaults:"
    grep -oP 'x-stainless-[a-z-]+.*?:.*' "$CRS_PATH/src/services/claudeCodeHeadersService.js" 2>/dev/null | head -10 | sed 's/^/  /'
fi

echo ""
if [ -d "$SUB2API_PATH" ]; then
    echo "sub2api defaults:"
    grep -oP '"X-Stainless-[^"]*":\s*"[^"]*"' "$SUB2API_PATH/backend/internal/pkg/claude/constants.go" 2>/dev/null | sed 's/^/  /'
fi

# --- 6. OAuth Scopes ---
echo ""
echo "=== 6. OAuth Scopes ==="
echo ""

echo "Claude Code: org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

if [ -d "$CRS_PATH" ]; then
    echo -n "CRS:         "
    grep -oP "scope.*?\[.*?\]" "$CRS_PATH/src/utils/oauthHelper.js" 2>/dev/null | head -1 || echo "see source"
fi

if [ -d "$SUB2API_PATH" ]; then
    echo -n "sub2api:     "
    grep -A5 'ScopesBrowser' "$SUB2API_PATH/backend/internal/pkg/oauth/oauth.go" 2>/dev/null | grep -oP '"[^"]*"' | tr '\n' ' ' || echo "see source"
    echo ""
fi

# --- 7. metadata.user_id handling ---
echo ""
echo "=== 7. metadata.user_id Rewriting ==="
echo ""

echo "Claude Code: sends real device_id + account_uuid + session_id"

if [ -d "$CRS_PATH" ]; then
    echo -n "CRS:         "
    if grep -q "device_id\|deviceId" "$CRS_PATH/src/utils/metadataUserIdHelper.js" 2>/dev/null; then
        echo "rewrites account_uuid + hashes session_id (keeps device_id)"
    else
        echo "not found"
    fi
fi

if [ -d "$SUB2API_PATH" ]; then
    echo -n "sub2api:     "
    if grep -q "device_id\|DeviceID\|ClientID" "$SUB2API_PATH/backend/internal/service/metadata_userid.go" 2>/dev/null; then
        echo "rewrites device_id + account_uuid + hashes session_id"
    else
        echo "not found"
    fi
fi

echo ""
echo "========================================================"
echo " Done. Review above for mismatches (✗) and warnings."
echo "========================================================"
