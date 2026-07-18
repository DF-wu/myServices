#!/bin/sh
set -eu

# Read-only host gate for dashboard Docker socket proxies. The proxy must be
# reachable on its private bridge address, but Docker container metadata and
# filesystem endpoints must not be exposed to the dashboard process.

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s [PROXY_NAME ...]\n' "$0" >&2
  printf 'Defaults: homepage-dockerproxy glance-dockerproxy\n' >&2
  exit 64
}

if [ "$#" -eq 0 ]; then
  set -- homepage-dockerproxy glance-dockerproxy
fi
[ "$#" -ge 1 ] || usage

for command_name in docker jq curl awk
do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "required command not found: $command_name"
done

valid_name() {
  case $1 in
    ''|[!A-Za-z0-9]*|*[!A-Za-z0-9_.-]*) return 1 ;;
    *) return 0 ;;
  esac
}

valid_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 { exit 1 }
    {
      for (i = 1; i <= 4; i++) {
        if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255 ||
            (length($i) > 1 && substr($i, 1, 1) == "0") ) exit 1
      }
    }
  '
}

http_status() {
  request_url=$1
  # Disable curl configuration files and all ambient proxy variables. Bodies
  # are discarded so a misconfigured endpoint cannot print a secret here.
  curl --disable --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --connect-timeout 2 --max-time 5 \
    --limit-rate 64k --noproxy '*' "$request_url" 2>/dev/null
}

require_success() {
  status=$1
  description=$2
  case $status in
    2[0-9][0-9]) ;;
    [0-9][0-9][0-9]) die "$description did not respond successfully (HTTP $status)" ;;
    *) die "$description returned an invalid HTTP status" ;;
  esac
}

require_denied() {
  status=$1
  description=$2
  case $status in
    2[0-9][0-9]) die "$description is exposed (HTTP $status)" ;;
    1[0-9][0-9]|3[0-9][0-9]|4[0-9][0-9]|5[0-9][0-9]) ;;
    *) die "$description returned an invalid HTTP status" ;;
  esac
}

check_proxy() {
  proxy_name=$1
  valid_name "$proxy_name" || die "invalid Docker proxy name: $proxy_name"

  inspect_json=$(docker inspect --type container "$proxy_name" 2>/dev/null) ||
    die "Docker read proxy is missing or cannot be inspected: $proxy_name"
  [ -n "$inspect_json" ] ||
    die "Docker inspect returned no data for read proxy: $proxy_name"

  object_count=$(printf '%s\n' "$inspect_json" | jq -er 'length' 2>/dev/null) ||
    die "Docker inspect returned invalid JSON for read proxy: $proxy_name"
  [ "$object_count" = 1 ] ||
    die "Docker inspect returned an unexpected object count for read proxy: $proxy_name"

  running=$(printf '%s\n' "$inspect_json" | jq -er '.[0].State.Running == true' 2>/dev/null) ||
    die "Docker read proxy has no usable running state: $proxy_name"
  [ "$running" = true ] ||
    die "Docker read proxy is not running: $proxy_name"

  proxy_id=$(printf '%s\n' "$inspect_json" | jq -er '.[0].Id' 2>/dev/null) ||
    die "Docker read proxy has no container ID: $proxy_name"
  case $proxy_id in
    ''|*[!0-9a-fA-F]*) die "Docker read proxy returned an invalid container ID: $proxy_name" ;;
  esac

  network_count=$(printf '%s\n' "$inspect_json" | jq -er '
    [.[0].NetworkSettings.Networks // {} | to_entries[] |
      select((.value.IPAddress // "") != "")] | length
  ' 2>/dev/null) ||
    die "Docker read proxy has no bridge network address: $proxy_name"
  [ "$network_count" = 1 ] ||
    die "Docker read proxy must have exactly one bridge IPv4 address: $proxy_name"
  proxy_ip=$(printf '%s\n' "$inspect_json" | jq -er '
    [.[0].NetworkSettings.Networks // {} | to_entries[] |
      select((.value.IPAddress // "") != "") | .value.IPAddress][0]
  ' 2>/dev/null) ||
    die "Docker read proxy bridge address is unavailable: $proxy_name"
  valid_ipv4 "$proxy_ip" ||
    die "Docker read proxy returned an invalid bridge IPv4 address: $proxy_name"

  exposed_port=$(printf '%s\n' "$inspect_json" | jq -er '
    [.[0].Config.ExposedPorts // {} | keys[] | select(. == "2375/tcp")] | length
  ' 2>/dev/null) ||
    die "Docker read proxy does not expose the reviewed TCP port: $proxy_name"
  [ "$exposed_port" = 1 ] ||
    die "Docker read proxy must expose exactly the reviewed 2375/tcp port: $proxy_name"

  host_bindings=$(printf '%s\n' "$inspect_json" | jq -er '
    ((.[0].NetworkSettings.Ports // {})["2375/tcp"] // []) | length
  ' 2>/dev/null) ||
    die "Docker read proxy port mapping is unavailable: $proxy_name"
  [ "$host_bindings" = 0 ] ||
    die "Docker read proxy 2375/tcp must not be published on the host: $proxy_name"

  base_url=http://$proxy_ip:2375
  status=$(http_status "$base_url/_ping") ||
    die "Docker read proxy health request failed: $proxy_name"
  require_success "$status" "Docker read proxy health endpoint: $proxy_name"

  # Use the proxy container itself as a harmless target. Every path below is
  # a GET endpoint that can disclose metadata, command lines, logs, or files.
  while IFS='|' read -r label path
  do
    [ -n "$label" ] || continue
    status=$(http_status "$base_url$path") ||
      die "Docker read proxy request failed for $label: $proxy_name"
    require_denied "$status" "Docker read proxy $label endpoint: $proxy_name"
  done <<EOF
inspect|/containers/$proxy_id/json
top|/containers/$proxy_id/top?ps_args=-o%20pid
archive|/containers/$proxy_id/archive?path=%2Fetc%2Fhostname
logs|/containers/$proxy_id/logs?stdout=1&stderr=1&tail=0
export|/containers/$proxy_id/export
changes|/containers/$proxy_id/changes
EOF

  printf 'Docker read proxy safety gate passed: %s (%s:2375)\n' \
    "$proxy_name" "$proxy_ip"
}

for proxy_name
do
  check_proxy "$proxy_name"
done
