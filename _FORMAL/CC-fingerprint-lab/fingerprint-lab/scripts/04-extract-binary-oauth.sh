#!/bin/bash
# 從 Claude Code SEA binary 中提取所有 OAuth 相關程式碼段和常數
# 用法: ./04-extract-binary-oauth.sh [binary_path] [output_dir]

set -euo pipefail

BINARY="${1:-/opt/claude-code/bin/claude}"
OUTPUT="${2:-/tmp/fingerprint-lab/evidence}"

if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY"
    exit 1
fi

mkdir -p "$OUTPUT"

echo "Extracting OAuth evidence from: $BINARY"
echo "Output directory: $OUTPUT"
echo ""

# 1. OAuth 常數 (endpoints, client_id, scopes)
echo "--- 1. OAuth Constants ---"
strings "$BINARY" | grep -oP '.{0,300}(TOKEN_URL|AUTHORIZE_URL|CLIENT_ID|REDIRECT|MANUAL_REDIRECT|API_KEY_URL|ROLES_URL|SUCCESS_URL).{0,300}' \
    | grep -i 'claude\|anthropic' \
    | sort -u > "$OUTPUT/oauth_constants.txt"
echo "  → $OUTPUT/oauth_constants.txt ($(wc -l < "$OUTPUT/oauth_constants.txt") lines)"

# 2. Token Exchange 函數
echo "--- 2. Token Exchange Function ---"
strings "$BINARY" | grep -oP '.{0,100}DA\.post\(rL\(\)\.TOKEN_URL.{0,300}' \
    > "$OUTPUT/token_exchange_function.txt"
echo "  → $OUTPUT/token_exchange_function.txt ($(wc -l < "$OUTPUT/token_exchange_function.txt") lines)"

# 3. Token Refresh 函數
echo "--- 3. Token Refresh Function ---"
strings "$BINARY" | grep -oP '.{0,200}grant_type.*refresh_token.{0,500}' \
    | grep -i 'DA.post\|TOKEN_URL\|headers' \
    > "$OUTPUT/token_refresh_function.txt"
echo "  → $OUTPUT/token_refresh_function.txt ($(wc -l < "$OUTPUT/token_refresh_function.txt") lines)"

# 4. axios 版本和 UA 設定
echo "--- 4. Axios Version & UA Logic ---"
{
    echo "# Axios VERSION variable:"
    strings "$BINARY" | grep -oP 'W8H="[^"]*"' | sort -u
    echo ""
    echo "# Axios default UA logic:"
    strings "$BINARY" | grep -oP '.{0,50}User-Agent.*axios.{0,50}' | grep -v 'mozilla\|chrome' | sort -u
    echo ""
    echo "# All axios-related version strings:"
    strings "$BINARY" | grep -oP 'axios[/"]\K[0-9]+\.[0-9]+\.[0-9]+' | sort -u
} > "$OUTPUT/axios_version.txt"
echo "  → $OUTPUT/axios_version.txt"

# 5. UA 建構函數
echo "--- 5. User-Agent Builder Functions ---"
{
    echo "# vV() — API request UA:"
    strings "$BINARY" | grep -oP 'function vV\(\).{0,500}' | head -2
    echo ""
    echo "# co() — MCP/WebSocket UA:"
    strings "$BINARY" | grep -oP 'function co\(\).{0,500}' | head -2
    echo ""
    echo "# jO() — Client Data/Metrics UA:"
    strings "$BINARY" | grep -oP 'function jO\(\).{0,300}' | head -2
} > "$OUTPUT/ua_functions.txt"
echo "  → $OUTPUT/ua_functions.txt"

# 6. Beta flags
echo "--- 6. Beta Flags ---"
strings "$BINARY" | grep -oP '[a-z-]+-20[0-9]{2}-[0-9]{2}-[0-9]{2}' | sort -u \
    > "$OUTPUT/beta_flags.txt"
echo "  → $OUTPUT/beta_flags.txt ($(wc -l < "$OUTPUT/beta_flags.txt") flags)"

# 7. x-stainless headers 相關
echo "--- 7. X-Stainless Headers ---"
strings "$BINARY" | grep -i 'x-stainless' | grep -v 'node_modules\|test\|spec' | sort -u \
    > "$OUTPUT/stainless_headers.txt"
echo "  → $OUTPUT/stainless_headers.txt ($(wc -l < "$OUTPUT/stainless_headers.txt") lines)"

# 8. Node.js 版本
echo "--- 8. Bundled Node.js Version ---"
{
    echo "Node.js version in binary:"
    strings "$BINARY" | grep -oP 'node/v[0-9]+\.[0-9]+\.[0-9]+' | sort -u
} > "$OUTPUT/nodejs_version.txt"
echo "  → $OUTPUT/nodejs_version.txt"

# 9. OAuth scopes
echo "--- 9. OAuth Scopes ---"
{
    echo "All scopes found:"
    strings "$BINARY" | grep -oP '(user|org):[a-z_:]+' | sort -u
} > "$OUTPUT/oauth_scopes.txt"
echo "  → $OUTPUT/oauth_scopes.txt"

# 10. Credential storage paths
echo "--- 10. Credential Storage ---"
{
    strings "$BINARY" | grep -i 'credentials\|credential\|keychain\|\.claude' | grep -i 'json\|path\|store\|key' | sort -u
} > "$OUTPUT/credential_storage.txt"
echo "  → $OUTPUT/credential_storage.txt ($(wc -l < "$OUTPUT/credential_storage.txt") lines)"

echo ""
echo "Done. All evidence extracted to $OUTPUT/"
ls -la "$OUTPUT/"
