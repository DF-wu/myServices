#!/bin/bash
# 從 Claude Code binary 或 npm tarball 提取 bundled axios 版本
# 用法:
#   ./01-extract-axios-version.sh                    # 從本地 binary
#   ./01-extract-axios-version.sh 2.1.81             # 從 npm 特定版本
#   ./01-extract-axios-version.sh all                # 掃描所有主要版本

set -euo pipefail

extract_from_binary() {
    local binary="${1:-/opt/claude-code/bin/claude}"
    if [ ! -f "$binary" ]; then
        echo "Error: binary not found at $binary"
        exit 1
    fi

    echo "=== Extracting from binary: $binary ==="

    # Claude Code 版本
    local cc_version
    cc_version=$("$binary" --version 2>/dev/null | head -1 || echo "unknown")
    echo "Claude Code version: $cc_version"

    # bundled axios VERSION 變數名和值
    local axios_var
    axios_var=$(strings "$binary" | grep -oP '"User-Agent","axios/"\+\K\w+' | head -1)
    if [ -n "$axios_var" ]; then
        local axios_ver
        axios_ver=$(strings "$binary" | grep -oP "${axios_var}=\"\K[0-9]+\.[0-9]+\.[0-9]+" | head -1)
        echo "Bundled axios version: ${axios_ver} (var: ${axios_var})"
        echo "Token UA: axios/${axios_ver}"
    else
        echo "Could not find axios version variable"
    fi

    # Token Endpoint
    echo ""
    echo "Token Endpoint:"
    strings "$binary" | grep -oP 'TOKEN_URL:"[^"]*"' | head -1

    # CLI UA 函數
    echo ""
    echo "CLI UA (VERSION):"
    strings "$binary" | grep -oP 'VERSION:"[0-9]+\.[0-9]+\.[0-9]+"' | sort -u

    # Node.js version
    echo ""
    echo "Bundled Node.js:"
    strings "$binary" | grep -oP 'node/v[0-9]+\.[0-9]+\.[0-9]+' | sort -u

    # OAuth Client ID
    echo ""
    echo "OAuth Client ID:"
    strings "$binary" | grep -oP '9d1c250a-e61b-44d9-88ed-5944d1962f5e' | head -1

    # OAuth Scopes
    echo ""
    echo "OAuth Scopes:"
    strings "$binary" | grep -oP 'user:inference|user:profile|user:sessions:claude_code|user:mcp_servers|user:file_upload|org:create_api_key' | sort -u
}

extract_from_npm() {
    local version="$1"
    local tarball
    tarball=$(npm view "@anthropic-ai/claude-code@${version}" dist.tarball 2>/dev/null)
    if [ -z "$tarball" ]; then
        echo "claude-code@${version}: not available"
        return
    fi

    local axios_var
    axios_var=$(curl -sL "$tarball" | tar xzO --wildcards '*/cli.*js' 2>/dev/null | grep -oP '"User-Agent","axios/"\+\K\w+' | head -1)
    if [ -n "$axios_var" ]; then
        local axios_ver
        axios_ver=$(curl -sL "$tarball" | tar xzO --wildcards '*/cli.*js' 2>/dev/null | grep -oP "${axios_var}=\"\K[0-9]+\.[0-9]+\.[0-9]+" | head -1)

        local cli_ver
        cli_ver=$(curl -sL "$tarball" | tar xzO --wildcards '*/cli.*js' 2>/dev/null | grep -oP 'VERSION:"[0-9]+\.[0-9]+\.[0-9]+"' | tail -1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')

        echo "claude-code@${version}: CLI=claude-cli/${cli_ver:-unknown} | Token=axios/${axios_ver}"
    else
        echo "claude-code@${version}: axios version not found in bundle"
    fi
}

scan_all_versions() {
    echo "=== Scanning all major Claude Code versions ==="
    echo ""
    printf "%-25s %-30s %s\n" "Claude Code" "CLI UA" "Token UA"
    printf "%-25s %-30s %s\n" "-------------------------" "------------------------------" "-------------------"

    for v in 1.0.3 1.0.6 1.0.8 1.0.16 1.0.18 \
             2.0.0 2.0.2 2.0.5 \
             2.1.0 2.1.10 2.1.22 2.1.44 2.1.67 2.1.72 \
             2.1.78 2.1.80 2.1.81 2.1.83 2.1.85 2.1.87; do
        extract_from_npm "$v"
    done
}

# Main
case "${1:-local}" in
    local)
        extract_from_binary "${2:-/opt/claude-code/bin/claude}"
        ;;
    all)
        scan_all_versions
        ;;
    *)
        extract_from_npm "$1"
        ;;
esac
