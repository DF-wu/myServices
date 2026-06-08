#!/usr/bin/env bash
set -euo pipefail

CFG=${ASTRBOT_CONFIG:-/mnt/appdata/ChatStack/astrbot/data/cmd_config.json}
ASTRBOT_CONTAINER=${ASTRBOT_CONTAINER:-astrbot}
LEGACY_CONTAINER=${LEGACY_CONTAINER:-telegram-chatbot}
DASHBOARD_URL=${DASHBOARD_URL:-http://127.0.0.1:43004}
NEW_API_STATUS_URL=${NEW_API_STATUS_URL:-http://127.0.0.1:43001/api/status}
TEST_MODEL=${TEST_MODEL:-gemini-3-flash-preview}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

ok() {
  printf 'OK  %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

need curl
need docker
need jq

[[ -f "$CFG" ]] || fail "AstrBot config not found: $CFG"

astrbot_status=$(docker inspect "$ASTRBOT_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || true)
[[ "$astrbot_status" == "running" ]] || fail "$ASTRBOT_CONTAINER is not running (status: ${astrbot_status:-missing})"
ok "$ASTRBOT_CONTAINER is running"

legacy_status=$(docker inspect "$LEGACY_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || true)
legacy_restart=$(docker inspect "$LEGACY_CONTAINER" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || true)
[[ "$legacy_status" != "running" ]] || fail "$LEGACY_CONTAINER is still running"
[[ "$legacy_restart" == "no" || -z "$legacy_restart" ]] || fail "$LEGACY_CONTAINER restart policy is $legacy_restart"
ok "$LEGACY_CONTAINER is stopped"

dashboard_version=$(curl -fsS "$DASHBOARD_URL/assets/version")
[[ "$dashboard_version" == "v4.25.1" ]] || fail "unexpected dashboard version: $dashboard_version"
ok "AstrBot dashboard version is $dashboard_version"

new_api_ok=$(curl -fsS "$NEW_API_STATUS_URL" | jq -r '.success')
[[ "$new_api_ok" == "true" ]] || fail "new-api status endpoint is not successful"
ok "new-api status endpoint is healthy"

platform_type=$(jq -r '.platform[] | select(.id=="telegram") | .type' "$CFG")
platform_enabled=$(jq -r '.platform[] | select(.id=="telegram") | .enable' "$CFG")
[[ "$platform_type" == "telegram" && "$platform_enabled" == "true" ]] || fail "Telegram platform is not enabled in AstrBot config"
ok "AstrBot Telegram platform is enabled"

api_base=$(jq -r '.provider_sources[] | select(.id=="openai") | .api_base' "$CFG")
default_provider=$(jq -r '.provider_settings.default_provider_id' "$CFG")
[[ "$api_base" == "http://new-api:3000/v1" ]] || fail "unexpected provider api_base: $api_base"
[[ "$default_provider" == "openai/$TEST_MODEL" ]] || fail "unexpected default provider: $default_provider"
ok "AstrBot provider points to internal new-api"

api_key=$(jq -r '.provider_sources[] | select(.id=="openai") | .key | if type == "array" then .[0] else . end' "$CFG")
model_response=$(
  docker exec "$ASTRBOT_CONTAINER" curl -fsS \
    -H "Authorization: Bearer ${api_key}" \
    -H 'Content-Type: application/json' \
    http://new-api:3000/v1/chat/completions \
    -d "{\"model\":\"$TEST_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly OK. No explanation.\"}],\"max_tokens\":256}"
)
model_error=$(jq -r '.error.message // empty' <<<"$model_response")
[[ -z "$model_error" ]] || fail "provider test returned error: $model_error"
model_choice_count=$(jq -r '.choices | length' <<<"$model_response")
[[ "$model_choice_count" -gt 0 ]] || fail "provider test returned no choices"
ok "AstrBot container can call $TEST_MODEL through new-api"

bot_token=$(jq -r '.platform[] | select(.id=="telegram") | .telegram_token' "$CFG")
webhook_info=$(curl -fsS "https://api.telegram.org/bot${bot_token}/getWebhookInfo")
webhook_url=$(jq -r '.result.url' <<<"$webhook_info")
webhook_error=$(jq -r '.result.last_error_message // empty' <<<"$webhook_info")
[[ -z "$webhook_url" ]] || fail "Telegram webhook is still set: $webhook_url"
[[ -z "$webhook_error" ]] || fail "Telegram webhook reports error: $webhook_error"
ok "Telegram webhook is clear for polling"

bot_info=$(curl -fsS "https://api.telegram.org/bot${bot_token}/getMe")
bot_username=$(jq -r '.result.username' <<<"$bot_info")
[[ -n "$bot_username" && "$bot_username" != "null" ]] || fail "Telegram getMe did not return a username"
ok "Telegram getMe works for @$bot_username"

started_at=$(docker inspect "$ASTRBOT_CONTAINER" --format '{{.State.StartedAt}}')
recent_log=$(docker logs --since "$started_at" "$ASTRBOT_CONTAINER" 2>&1 | sed -r 's/\x1B\[[0-9;]*[mK]//g')
if grep -Eq 'ERRO|WebUI version mismatch|polling request failed|mnemosyne' <<<"$recent_log"; then
  echo "$recent_log" | grep -En 'ERRO|WebUI version mismatch|polling request failed|mnemosyne' >&2
  fail "AstrBot logs contain errors after latest start"
fi
grep -q 'Telegram Platform Adapter is running' <<<"$recent_log" || fail "Telegram polling startup was not found in AstrBot logs"
ok "AstrBot logs confirm Telegram polling is running"

echo "All automated AstrBot Telegram checks passed."
