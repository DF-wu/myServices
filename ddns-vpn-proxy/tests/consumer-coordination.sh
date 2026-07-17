#!/bin/sh
set -eu

# 使用 PATH 內的 fake docker/wget/nc 驗證 namespace consumer 協調。
# 不連線 Docker daemon，也不建立、啟動、停止或重啟真實 container。

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
subject=$repo_root/scripts/ddns-openvpn.sh
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_equals() {
  expected=$1
  actual=$2
  description=$3
  [ "$expected" = "$actual" ] ||
    fail "$description (expected '$expected', got '$actual')"
}

new_fixture() {
  name=$1
  fixture=$workdir/$name
  mkdir -p "$fixture/source" "$fixture/state/ddns" "$fixture/state/runtime" "$fixture/bin"

  cat >"$fixture/source/client.ovpn" <<'EOF'
client
dev tun
proto udp
remote vpn.example.test 1194 udp
EOF

  cat >"$fixture/bin/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$DOCKER_LOG"

case $1:$2 in
  container:inspect)
    case ${DEPENDENT_STATE:-running} in
      running) printf 'true\n' ;;
      stopped) printf 'false\n' ;;
      absent)
        printf 'Error response from daemon: No such container: dependent-test\n' >&2
        exit 1
        ;;
      error)
        printf 'Error response from daemon: permission denied\n' >&2
        exit 1
        ;;
    esac
    ;;
  container:restart)
    last=
    for argument do last=$argument; done
    if [ "$last" = dependent-test ] && [ "${DEPENDENT_RESTART_FAIL:-0}" = 1 ]; then
      exit 1
    fi
    ;;
esac
EOF

  cat >"$fixture/bin/wget" <<'EOF'
#!/bin/sh
exit 0
EOF

  cat >"$fixture/bin/nc" <<'EOF'
#!/bin/sh
exit 0
EOF

  chmod +x "$fixture/bin/docker" "$fixture/bin/wget" "$fixture/bin/nc"
  printf '%s\n' "$fixture"
}

run_subject() {
  fixture=$1
  shift
  PATH="$fixture/bin:$PATH" \
  STATE_DIR="$fixture/state" \
  VPN_TYPE=openvpn \
  VPN_SOURCE_CONFIG="$fixture/source/client.ovpn" \
  VPN_RENDERED_CONFIG="$fixture/state/runtime/vpn.conf" \
  DDNS_HOSTNAME=vpn.example.test \
  DDNS_OVERRIDE_IPS=198.51.100.20 \
  DDNS_POLL_SECONDS=10 \
  DDNS_INIT_RETRY_SECONDS=1 \
  PROXY_BIND_ADDRESS=127.0.0.1 \
  GLUETUN_CONTAINER_NAME=gluetun-test \
  VPROXY_CONTAINER_NAME=vproxy-test \
  DEPENDENT_CONTAINER_NAME=dependent-test \
  GLUETUN_RESTART_TIMEOUT_SECONDS=5 \
  GLUETUN_HEALTH_TIMEOUT_SECONDS=5 \
  GLUETUN_HEALTHCHECK_URL=http://gluetun:9999 \
  DOCKER_LOG="$fixture/docker.log" \
  "$@" sh "$subject" watch-once
}

seed_old_state() {
  fixture=$1
  printf '198.51.100.10\n' >"$fixture/state/ddns/last-ip"
  # 任意舊 hash 即可觸發完整 address-change lifecycle。
  printf 'old-profile-hash\n' >"$fixture/state/ddns/source.sha256"
  printf 'remote 198.51.100.10 1194 udp\n' >"$fixture/state/runtime/vpn.conf"
}

fixture=$(new_fixture running)
seed_old_state "$fixture"
run_subject "$fixture" env DEPENDENT_STATE=running >/dev/null
assert_equals '198.51.100.20' "$(cat "$fixture/state/ddns/last-ip")" \
  'running consumer flow must commit the new IP'
[ ! -e "$fixture/state/ddns/pending-dependent" ] ||
  fail 'running consumer flow must clear pending marker'
assert_equals 'container restart --timeout 5 -- gluetun-test
container restart --timeout 5 -- vproxy-test
container inspect --format {{.State.Running}} -- dependent-test
container restart --timeout 5 -- dependent-test' "$(cat "$fixture/docker.log")" \
  'running consumer must restart after Gluetun and vproxy'
printf 'ok - running consumer is reattached after VPN namespace change\n'

fixture=$(new_fixture stopped)
seed_old_state "$fixture"
run_subject "$fixture" env DEPENDENT_STATE=stopped >/dev/null
grep -Fq 'container inspect --format {{.State.Running}} -- dependent-test' "$fixture/docker.log" ||
  fail 'stopped consumer must be inspected'
if grep -Fq 'container restart --timeout 5 -- dependent-test' "$fixture/docker.log"; then
  fail 'stopped consumer must not be started/restarted'
fi
printf 'ok - stopped consumer remains stopped\n'

fixture=$(new_fixture absent)
seed_old_state "$fixture"
run_subject "$fixture" env DEPENDENT_STATE=absent >/dev/null
if grep -Fq 'container restart --timeout 5 -- dependent-test' "$fixture/docker.log"; then
  fail 'absent consumer must not be started/restarted'
fi
printf 'ok - absent consumer remains absent\n'

fixture=$(new_fixture retry)
seed_old_state "$fixture"
if run_subject "$fixture" env DEPENDENT_STATE=running DEPENDENT_RESTART_FAIL=1 >/dev/null 2>&1; then
  fail 'consumer restart failure must make the iteration retryable'
fi
assert_equals '198.51.100.20' "$(cat "$fixture/state/ddns/last-ip")" \
  'consumer-only failure must still commit healthy VPN state'
[ -s "$fixture/state/ddns/pending-dependent" ] ||
  fail 'consumer restart failure must retain pending marker'

: >"$fixture/docker.log"
run_subject "$fixture" env DEPENDENT_STATE=running DEPENDENT_RESTART_FAIL=0 >/dev/null
assert_equals 'container inspect --format {{.State.Running}} -- dependent-test
container restart --timeout 5 -- dependent-test' "$(cat "$fixture/docker.log")" \
  'consumer retry must not bounce Gluetun or vproxy again'
[ ! -e "$fixture/state/ddns/pending-dependent" ] ||
  fail 'successful consumer retry must clear pending marker'
printf 'ok - consumer-only retry does not restart the healthy VPN stack\n'

fixture=$(new_fixture shadowsocks-gate)
validate_with_shadow_flag() {
  configured=$1
  PATH="$fixture/bin:$PATH" \
  STATE_DIR="$fixture/state" \
  VPN_TYPE=openvpn \
  VPN_SOURCE_CONFIG="$fixture/source/client.ovpn" \
  VPN_RENDERED_CONFIG="$fixture/state/runtime/vpn.conf" \
  DDNS_HOSTNAME=vpn.example.test \
  DDNS_POLL_SECONDS=10 \
  DDNS_INIT_RETRY_SECONDS=1 \
  PROXY_BIND_ADDRESS=0.0.0.0 \
  HTTPPROXY_ENABLED=on \
  HTTPPROXY_USER_CONFIGURED=1 \
  HTTPPROXY_PASSWORD_CONFIGURED=1 \
  SOCKS5_USER_CONFIGURED=1 \
  SOCKS5_PASSWORD_CONFIGURED=1 \
  SHADOWSOCKS_ENABLED=on \
  SHADOWSOCKS_PASSWORD_CONFIGURED="$configured" \
  GLUETUN_CONTAINER_NAME=gluetun-test \
  VPROXY_CONTAINER_NAME=vproxy-test \
  GLUETUN_RESTART_TIMEOUT_SECONDS=5 \
  GLUETUN_HEALTH_TIMEOUT_SECONDS=5 \
  sh "$subject" validate
}

if validate_with_shadow_flag 0 >/dev/null 2>&1; then
  fail 'public Shadowsocks without a password must fail closed'
fi
validate_with_shadow_flag 1 >/dev/null
printf 'ok - public legacy Shadowsocks requires a password\n'
