#!/bin/sh
set -eu

# Prove the rendered-model gate rejects changes to execution order, images and
# container privilege. The fixture uses the real installed assets but never
# creates, starts, stops or inspects a Docker object.

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
workdir=$(mktemp -d)
fixture=$workdir/repo
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

mkdir -p "$fixture/scripts" "$fixture/portainer"
cp -- "$repo_root/docker-compose.yml" "$fixture/docker-compose.yml"
cp -- "$repo_root/scripts/validate-portainer-env.sh" \
  "$fixture/scripts/validate-portainer-env.sh"
cp -- "$repo_root/scripts/ddns-openvpn.sh" "$fixture/scripts/ddns-openvpn.sh"
install -m 0600 -- "$repo_root/portainer/jp.env.example" "$fixture/portainer/jp.env"

validator=$fixture/scripts/validate-portainer-env.sh
compose=$fixture/docker-compose.yml
baseline=$workdir/docker-compose.baseline.yml
env_file=$fixture/portainer/jp.env
env_baseline=$workdir/jp.env.baseline
cp -- "$compose" "$baseline"
cp -- "$env_file" "$env_baseline"

run_validator() {
  sh "$validator" jp ddns-vpn-proxy-jp "$fixture/portainer/jp.env"
}

run_validator >/dev/null || fail 'reviewed Portainer model was rejected'
printf 'ok - reviewed Portainer model is accepted\n'

reject_mutation() {
  description=$1
  expression=$2
  cp -- "$baseline" "$compose"
  cp -- "$env_baseline" "$env_file"
  sed "$expression" "$baseline" >"$compose"
  cmp -s "$baseline" "$compose" && fail "test mutation did not apply: $description"
  if run_validator >/dev/null 2>&1; then
    fail "$description"
  fi
}

reject_env_mutation() {
  description=$1
  expression=$2
  cp -- "$baseline" "$compose"
  sed "$expression" "$env_baseline" >"$env_file"
  cmp -s "$env_baseline" "$env_file" && fail "env test mutation did not apply: $description"
  chmod 0600 "$env_file"
  if run_validator >/dev/null 2>&1; then
    fail "$description"
  fi
}

reject_mutation 'ddns-init command mutation was accepted' \
  's/^      - init$/      - help/'
reject_mutation 'startup dependency mutation was accepted' \
  's/condition: service_completed_successfully/condition: service_started/'
reject_mutation 'image pull policy mutation was accepted' \
  's/pull_policy: always/pull_policy: never/g'
reject_mutation 'capability drop mutation was accepted' \
  's/cap_drop:/x-cap-drop:/g'
reject_mutation 'read-only filesystem mutation was accepted' \
  's/read_only: true/read_only: false/g'
reject_mutation 'healthcheck mutation was accepted' \
  's/retries: 3/retries: 4/g'
reject_mutation 'helper image digest mutation was accepted' \
  's/28bd5fe8b56d1bd048e5babf5b10710e/08bd5fe8b56d1bd048e5babf5b10710e/'
# shellcheck disable=SC2016 # sed must preserve the literal Compose expansion.
reject_mutation 'point-of-use control auth check removal was accepted' \
  's/test "$${actual_auth}" = "$${expected_auth}"/test -n "$${actual_auth}"/'
reject_mutation 'appended point-of-use shell was accepted' \
  's/        exec \/gluetun-entrypoint/        touch \/tmp\/unexpected\n        exec \/gluetun-entrypoint/'
reject_mutation 'extra Gluetun environment control was accepted' \
  's/^      FIREWALL_INPUT_PORTS:/      FIREWALL=off\n      FIREWALL_INPUT_PORTS:/'
reject_mutation 'OpenVPN group-drop removal was accepted' \
  's/^      OPENVPN_FLAGS: --group nonrootuser --cipher AES-256-GCM --data-ciphers AES-256-GCM$/      OPENVPN_FLAGS: --verb 9/'
reject_mutation 'writable resolver removal was accepted' \
  's/^        read_only: false$/        read_only: true/'
reject_mutation 'external project network was accepted' \
  's/^volumes:$/networks:\n  default:\n    external: true\nvolumes:/'
reject_mutation 'external state volume was accepted' \
  's/^  vpn-state:$/  vpn-state:\n    external: true/'
reject_mutation 'GOST extra host gateway was accepted' \
  's/^    network_mode: service:gluetun$/    network_mode: service:gluetun\n    extra_hosts:\n      - host.docker.internal:host-gateway/'
reject_mutation 'GOST host root mount was accepted' \
  's/^    pids_limit: 64$/    pids_limit: 64\n    volumes:\n      - type: bind\n        source: \/\n        target: \/host\n        read_only: true/'
reject_mutation 'GOST Dockerfile mutation was accepted' \
  's#dockerfile: docker/gost.Dockerfile#dockerfile: docker/gluetun.Dockerfile#'
reject_mutation 'GOST extra device was accepted' \
  's/^    pids_limit: 64$/    pids_limit: 64\n    devices:\n      - \/dev\/null:\/dev\/null/'
reject_mutation 'GOST command expansion was accepted' \
  's/handler.udp=false/handler.udp=true/'
reject_mutation 'GOST root user was accepted' \
  's/^    user: "65532:65532"$/    user: "0:0"/'
reject_mutation 'GOST PID limit removal was accepted' \
  's/^    pids_limit: 64$/    pids_limit: -1/'
# shellcheck disable=SC2016 # sed must preserve the literal Compose expansion.
reject_mutation 'logging retention drift was accepted' \
  's/^    max-file: \${LOG_MAX_FILE:-3}$/    max-file: 99/'
reject_env_mutation 'public proxy binding was accepted' \
  's/^PROXY_BIND_ADDRESS=127.0.0.1$/PROXY_BIND_ADDRESS=0.0.0.0/'

printf 'ok - model gate rejects command, dependency, image, topology and privilege drift\n'
printf 'Portainer model safety tests passed.\n'
