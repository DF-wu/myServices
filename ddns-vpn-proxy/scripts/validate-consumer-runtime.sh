#!/bin/sh
set -eu

# Read-only gate for a network_mode:container consumer. A consumer in the
# Gluetun namespace can observe plaintext control traffic if it retains
# CAP_NET_RAW, so this check is a deployment prerequisite.

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] ||
  die "usage: $0 CONSUMER_NAME [GLUETUN_NAME]"
consumer=$1
gluetun=
if [ "$#" -eq 2 ]; then
  gluetun=$2
fi

case $consumer in
  ''|*[!A-Za-z0-9_.-]*) die 'container names must use Docker name characters only' ;;
esac
if [ -n "$gluetun" ]; then
  case $gluetun in
    ''|*[!A-Za-z0-9_.-]*) die 'Gluetun names must use Docker name characters only' ;;
  esac
fi

command -v docker >/dev/null 2>&1 || die 'docker CLI is required'
command -v jq >/dev/null 2>&1 || die 'jq is required'
command -v awk >/dev/null 2>&1 || die 'awk is required'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
consumer_json=$tmpdir/consumer.json
gluetun_json=$tmpdir/gluetun.json

if ! docker inspect --type container "$consumer" >"$consumer_json"; then
  die "consumer does not exist: $consumer"
fi
jq -e 'length == 1' "$consumer_json" >/dev/null ||
  die "consumer inspect returned an unexpected number of objects: $consumer"

jq -e '
  .[0].HostConfig.Privileged == false and
  ((.[0].HostConfig.CapDrop // []) | map(ascii_upcase) | index("ALL") != null) and
  ((.[0].HostConfig.CapAdd // []) | length == 0) and
  ((.[0].HostConfig.SecurityOpt // []) |
    any(.[]; . == "no-new-privileges" or . == "no-new-privileges:true")) and
  ((.[0].HostConfig.PidMode // "") == "")
' "$consumer_json" >/dev/null ||
  die "consumer must drop ALL capabilities, add none, use no-new-privileges, and not share a PID namespace: $consumer"

running=$(jq -r '.[0].State.Running // false' "$consumer_json")
if [ "$running" = true ]; then
  pid=$(jq -r '.[0].State.Pid // 0' "$consumer_json")
  case $pid in
    ''|*[!0-9]*) die "running consumer has no valid host PID: $consumer" ;;
  esac
  [ "$pid" -gt 0 ] || die "running consumer has no valid host PID: $consumer"
  [ -r "/proc/$pid/status" ] || die "cannot read effective capabilities for: $consumer"
  cap_eff=$(awk '$1 == "CapEff:" { print $2; found=1 } END { exit(found == 1 ? 0 : 1) }' \
    "/proc/$pid/status") || die "failed to read effective capabilities for: $consumer"
  no_new_privs=$(awk '$1 == "NoNewPrivs:" { print $2; found=1 } END { exit(found == 1 ? 0 : 1) }' \
    "/proc/$pid/status") || die "failed to read no-new-privileges state for: $consumer"
  case $cap_eff in
    ''|*[!0-9a-fA-F]*) die "consumer effective capability value is invalid: $consumer" ;;
  esac
  [ "$cap_eff" = 0000000000000000 ] ||
    die "consumer still has effective Linux capabilities (must be zero): $consumer"
  [ "$no_new_privs" = 1 ] ||
    die "consumer effective NoNewPrivs is not set: $consumer"
fi

if [ -n "$gluetun" ]; then
  if ! docker inspect --type container "$gluetun" >"$gluetun_json"; then
    die "Gluetun container does not exist: $gluetun"
  fi
  jq -e 'length == 1' "$gluetun_json" >/dev/null ||
    die "Gluetun inspect returned an unexpected number of objects: $gluetun"
  gluetun_id=$(jq -r '.[0].Id' "$gluetun_json")
  [ -n "$gluetun_id" ] && [ "$gluetun_id" != null ] ||
    die "Gluetun inspect did not return an ID: $gluetun"
  network_mode=$(jq -r '.[0].HostConfig.NetworkMode // ""' "$consumer_json")
  [ "$network_mode" = "container:$gluetun_id" ] ||
    die "consumer is not attached to the current Gluetun container ID: $consumer"
  [ "$running" = true ] || die "consumer is not running after namespace cutover: $consumer"
fi

printf 'Consumer capability and namespace gate passed: %s\n' "$consumer"
