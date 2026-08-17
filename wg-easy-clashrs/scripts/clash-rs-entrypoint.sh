#!/bin/sh
set -eu

config_file="/config/config.yaml"
template="/usr/local/share/clash-rs/config.example.yaml"

mkdir -p /config/providers

if [ ! -s "${config_file}" ]; then
  if [ -z "${CLASH_SUBSCRIPTION_URL:-}" ]; then
    echo "CLASH_SUBSCRIPTION_URL is required when ${config_file} does not exist" >&2
    exit 1
  fi

  cp "${template}" "${config_file}"
  CLASH_SUBSCRIPTION_URL="${CLASH_SUBSCRIPTION_URL}" \
    yq -i '.proxy-providers.subscription.url = strenv(CLASH_SUBSCRIPTION_URL)' "${config_file}"
  chmod 0600 "${config_file}"
fi

exec /usr/local/bin/clash-rs "$@"
