#!/bin/sh
set -eu

# Exercise in-place Gluetun control API reloads with fake nc/wget commands.
# No Docker socket is opened and no real container is touched.

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
subject=$repo_root/scripts/ddns-openvpn.sh
workdir=$(mktemp -d)

cleanup() {
  chmod -R u+rwX "$workdir" 2>/dev/null || :
  rm -rf "$workdir"
}

trap cleanup EXIT HUP INT TERM

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
  mkdir -p "$fixture/source" "$fixture/private" "$fixture/state/ddns" \
    "$fixture/state/runtime" "$fixture/bin"
  printf '%064d\n' 0 >"$fixture/private/control-api-key"
  printf '%064d\n' 1 >"$fixture/private/control-default-role.key"
  {
    printf '%s\n' '[[roles]]'
    printf '%s\n' 'name = "ddns-watcher"'
    printf '%s\n' 'auth = "apikey"'
    printf '%s\n' 'apikey = "0000000000000000000000000000000000000000000000000000000000000000"'
    printf '%s\n' 'routes = ["PUT /v1/vpn/status"]'
  } >"$fixture/private/control-auth.toml"
  printf '%s\n' '{"name":"deny-default","auth":"apikey","apikey":"0000000000000000000000000000000000000000000000000000000000000001"}' \
    >"$fixture/private/control-default-role.json"
  printf '%s\n' fixture-user >"$fixture/private/openvpn-user"
  printf '%s\n' fixture-password >"$fixture/private/openvpn-password"
  printf '%s\n' proxy-user >"$fixture/private/httpproxy-user"
  printf '%s\n' proxy-password >"$fixture/private/httpproxy-password"
  printf '%s\n' shadowsocks-password >"$fixture/private/shadowsocks-password"
  chmod 400 "$fixture/private/control-api-key" "$fixture/private/control-auth.toml" \
    "$fixture/private/control-default-role.json" "$fixture/private/openvpn-user" \
    "$fixture/private/openvpn-password" "$fixture/private/httpproxy-user" \
    "$fixture/private/httpproxy-password" "$fixture/private/shadowsocks-password"

  cat >"$fixture/source/client.ovpn" <<'EOF'
client
dev tun
proto udp
remote vpn.example.test 1194
remote-random
nobind
tun-mtu 1500
mssfix 1450
ping 15
ping-restart 0
reneg-sec 0
remote-cert-tls server
auth-user-pass
verb 3
fast-io
cipher AES-256-CBC
auth SHA512
<ca>
fixture-ca
</ca>
key-direction 1
<tls-auth>
fixture-tls-auth
</tls-auth>
EOF

  cat >"$fixture/bin/nc" <<'EOF'
#!/bin/sh
port=
for argument do port=$argument; done

case $port in
  8000)
    request=$(mktemp /tmp/fake-control-request.XXXXXX) || exit 1
    cat >"$request" || exit 1
    grep -Fq 'X-API-Key: 0000000000000000000000000000000000000000000000000000000000000000' \
      "$request" || exit 1
    first_line=$(sed -n '1{s/\r$//;p;}' "$request")
    case $first_line in
      'PUT /v1/vpn/status HTTP/1.1')
        if grep -Fq '"status":"stopped"' "$request"; then
          operation=stop
          failure=${CONTROL_STOP_FAIL:-0}
        else
          operation=start
          failure=${CONTROL_START_FAIL:-0}
        fi
        ;;
      *)
        operation=unexpected
        failure=1
        ;;
    esac
    printf '%s\n' "$operation" >>"$CONTROL_LOG"
    rm -f "$request"
    [ "$failure" = 0 ] || exit 1
    printf 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}'
    ;;
  1080)
    [ "${VPROXY_READY_FAIL:-0}" = 0 ] || exit 1
    request=$(mktemp /tmp/fake-socks-request.XXXXXX) || exit 1
    cat >"$request" || exit 1
    request_prefix=$(dd if="$request" bs=1 count=13 2>/dev/null |
      od -An -tx1 | tr -d ' \n')
    rm -f "$request"
    [ "$request_prefix" = 050100050100017f000001270f ] || exit 1
    case ${VPROXY_RESPONSE:-ok} in
      ok) printf '\005\000\005\000' ;;
      malformed) printf '\005\377\005\001' ;;
      empty) : ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

  cat >"$fixture/bin/wget" <<'EOF'
#!/bin/sh
[ "${GLUETUN_HEALTH_FAIL:-0}" = 0 ]
EOF

  cat >"$fixture/bin/sha256sum" <<'EOF'
#!/bin/sh
[ "${FAIL_SHA256SUM:-0}" = 0 ] || exit 1
exec /usr/bin/sha256sum "$@"
EOF

  cat >"$fixture/bin/nslookup" <<'EOF'
#!/bin/sh
exit 1
EOF

  cat >"$fixture/bin/date" <<'EOF'
#!/bin/sh
if [ "${FAST_TIME:-0}" = 1 ] && [ "${2:-}" = '+%s' ]; then
  counter=${TIME_COUNTER:?}
  value=0
  [ ! -r "$counter" ] || value=$(cat "$counter")
  value=$((value + 31))
  printf '%s\n' "$value" >"$counter"
  printf '%s\n' "$value"
  exit 0
fi
exec /usr/bin/date "$@"
EOF

  chmod +x "$fixture/bin/nc" "$fixture/bin/wget" "$fixture/bin/sha256sum" \
    "$fixture/bin/nslookup" "$fixture/bin/date"
  printf '%s\n' "$fixture"
}

run_subject() {
  fixture=$1
  command=$2
  shift 2
  profile_hash_line=$(/usr/bin/sha256sum "$fixture/source/client.ovpn") || return 1
  profile_hash=${profile_hash_line%% *}
  PATH="$fixture/bin:$PATH" \
  STATE_DIR="$fixture/state" \
  VPN_TYPE=openvpn \
  VPN_SOURCE_CONFIG="$fixture/source/client.ovpn" \
  VPN_SOURCE_SHA256="$profile_hash" \
  VPN_RENDERED_CONFIG="$fixture/state/runtime/vpn.conf" \
  GLUETUN_CONTROL_API_KEY_FILE="$fixture/private/control-api-key" \
  GLUETUN_CONTROL_AUTH_CONFIG_FILEPATH="$fixture/private/control-auth.toml" \
  GLUETUN_CONTROL_DEFAULT_ROLE_FILE="$fixture/private/control-default-role.json" \
  OPENVPN_USER_SECRETFILE="$fixture/private/openvpn-user" \
  OPENVPN_PASSWORD_SECRETFILE="$fixture/private/openvpn-password" \
  HTTPPROXY_USER_SECRETFILE="$fixture/private/httpproxy-user" \
  HTTPPROXY_PASSWORD_SECRETFILE="$fixture/private/httpproxy-password" \
  SHADOWSOCKS_PASSWORD_SECRETFILE="$fixture/private/shadowsocks-password" \
  GLUETUN_CONTROL_DEFAULT_ROLE_FILE="$fixture/private/control-default-role.json" \
  DDNS_HOSTNAME=vpn.example.test \
  DDNS_OVERRIDE_IPS=198.51.100.20 \
  DDNS_POLL_SECONDS=10 \
  DDNS_INIT_RETRY_SECONDS=1 \
  DDNS_INIT_TIMEOUT_SECONDS=30 \
  OPENVPN_USER_CONFIGURED=1 \
  OPENVPN_PASSWORD_CONFIGURED=1 \
  PROXY_BIND_ADDRESS=127.0.0.1 \
  GLUETUN_HEALTH_TIMEOUT_SECONDS=10 \
  GLUETUN_HEALTHCHECK_URL=http://gluetun:9999 \
  CONTROL_LOG="$fixture/control.log" \
  TIME_COUNTER="$fixture/time.counter" \
  "$@" sh "$subject" "$command"
}

seed_old_state() {
  fixture=$1
  printf '198.51.100.10\n' >"$fixture/state/ddns/last-ip"
  printf 'old-profile-hash\n' >"$fixture/state/ddns/source.sha256"
  printf 'remote 198.51.100.10 1194\n' >"$fixture/state/runtime/vpn.conf"
}

fixture=$(new_fixture fresh-init)
run_subject "$fixture" init env >/dev/null
assert_equals '198.51.100.20' "$(cat "$fixture/state/ddns/last-ip")" \
  'fresh init must record the first applied profile'
[ -s "$fixture/state/ddns/source.sha256" ] || fail 'fresh init must record source hash'
[ ! -e "$fixture/control.log" ] || fail 'init must not call the control API'
printf 'ok - fresh init records the first applied profile without control API access\n'

fixture=$(new_fixture update-init)
seed_old_state "$fixture"
run_subject "$fixture" init env >/dev/null
assert_equals '198.51.100.10' "$(cat "$fixture/state/ddns/last-ip")" \
  'update init must preserve the old applied IP'
assert_equals 'old-profile-hash' "$(cat "$fixture/state/ddns/source.sha256")" \
  'update init must preserve the old applied hash'
grep -Fq 'remote 198.51.100.20 1194' "$fixture/state/runtime/vpn.conf" ||
  fail 'update init must stage the newly rendered profile'
run_subject "$fixture" watch-once env >/dev/null
assert_equals 'stop
start' "$(cat "$fixture/control.log")" \
  'watcher must only stop and start the VPN loop in place'
assert_equals '198.51.100.20' "$(cat "$fixture/state/ddns/last-ip")" \
  'watcher must commit a successfully applied update'
printf 'ok - update init preserves state until an in-place reload succeeds\n'

for failure_stage in stop start
do
  fixture=$(new_fixture "control-$failure_stage-failure")
  seed_old_state "$fixture"
  case $failure_stage in
    stop) failure_env=CONTROL_STOP_FAIL=1 ;;
    start) failure_env=CONTROL_START_FAIL=1 ;;
  esac
  if run_subject "$fixture" watch env WATCH_ONCE=1 "$failure_env" >/dev/null 2>&1; then
    fail "control API $failure_stage failure must fail the production watcher"
  fi
  assert_equals '198.51.100.10' "$(cat "$fixture/state/ddns/last-ip")" \
    "control API $failure_stage failure must not commit the new IP"
done
printf 'ok - every control API failure leaves applied state uncommitted\n'

for response_mode in malformed empty
do
  fixture=$(new_fixture "socks-$response_mode")
  seed_old_state "$fixture"
  if run_subject "$fixture" watch env WATCH_ONCE=1 FAST_TIME=1 \
    VPROXY_RESPONSE="$response_mode" >/dev/null 2>&1; then
    fail "SOCKS5 $response_mode response must fail the production watcher"
  fi
  assert_equals '198.51.100.10' "$(cat "$fixture/state/ddns/last-ip")" \
    "SOCKS5 $response_mode response must not commit the new IP"
done
printf 'ok - watcher requires exact SOCKS5 greeting and CONNECT success bytes\n'

fixture=$(new_fixture source-hash-failure)
seed_old_state "$fixture"
if run_subject "$fixture" watch env WATCH_ONCE=1 FAIL_SHA256SUM=1 >/dev/null 2>&1; then
  fail 'production watch must fail when source hashing fails'
fi
[ ! -e "$fixture/control.log" ] || fail 'hash failure must not reload the VPN'
printf 'ok - source hash failure occurs before VPN reload\n'

fixture=$(new_fixture render-failure)
seed_old_state "$fixture"
printf 'not-a-directory\n' >"$fixture/state/render-parent"
if run_subject "$fixture" watch env WATCH_ONCE=1 \
  VPN_RENDERED_CONFIG="$fixture/state/render-parent/vpn.conf" >/dev/null 2>&1; then
  fail 'production watch must fail when profile rendering fails'
fi
[ ! -e "$fixture/control.log" ] || fail 'render failure must not reload the VPN'
printf 'ok - render failure occurs before VPN reload\n'

fixture=$(new_fixture heartbeat-failure)
seed_old_state "$fixture"
chmod 500 "$fixture/state/ddns"
if run_subject "$fixture" watch env WATCH_ONCE=1 >/dev/null 2>&1; then
  chmod 700 "$fixture/state/ddns"
  fail 'production watch must fail when heartbeat state is unwritable'
fi
chmod 700 "$fixture/state/ddns"
[ ! -e "$fixture/control.log" ] || fail 'heartbeat preflight failure must not reload the VPN'
printf 'ok - heartbeat preflight fails before VPN reload\n'

fixture=$(new_fixture init-timeout)
if run_subject "$fixture" init env DDNS_OVERRIDE_IPS= FAST_TIME=1 >/dev/null 2>&1; then
  fail 'DNS initialization must stop at the configured overall deadline'
fi
[ ! -e "$fixture/state/runtime/vpn.conf" ] || fail 'timed-out init must not publish a profile'
printf 'ok - DNS initialization has a bounded overall deadline\n'

fixture=$(new_fixture control-auth-mismatch)
chmod 700 "$fixture/private"
chmod 600 "$fixture/private/control-auth.toml"
{
  printf '%s\n' '[[roles]]'
  printf '%s\n' 'name = "ddns-watcher"'
  printf '%s\n' 'auth = "apikey"'
  printf '%s\n' 'apikey = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
  printf '%s\n' 'routes = ["PUT /v1/vpn/status"]'
} >"$fixture/private/control-auth.toml"
chmod 400 "$fixture/private/control-auth.toml"
chmod 500 "$fixture/private"
if run_subject "$fixture" init env >/dev/null 2>&1; then
  fail 'control auth key mismatch must fail before initialization'
fi
printf 'ok - control auth mismatch fails closed before profile publication\n'

fixture=$(new_fixture control-default-role-mismatch)
chmod 700 "$fixture/private"
chmod 600 "$fixture/private/control-default-role.json"
printf '%s\n' '{"name":"deny-default","auth":"apikey","apikey":"0000000000000000000000000000000000000000000000000000000000000000"}' \
  >"$fixture/private/control-default-role.json"
chmod 400 "$fixture/private/control-default-role.json"
chmod 500 "$fixture/private"
if run_subject "$fixture" init env >/dev/null 2>&1; then
  fail 'default role key reuse must fail before initialization'
fi
printf 'ok - default control role key reuse fails closed\n'

fixture=$(new_fixture public-proxy-gate)
validate_public() {
  bind_address=$1
  shadow_configured=$2
  profile_hash_line=$(/usr/bin/sha256sum "$fixture/source/client.ovpn") || return 1
  profile_hash=${profile_hash_line%% *}
  PATH="$fixture/bin:$PATH" \
  STATE_DIR="$fixture/state" \
  VPN_TYPE=openvpn \
  VPN_SOURCE_CONFIG="$fixture/source/client.ovpn" \
  VPN_SOURCE_SHA256="$profile_hash" \
  VPN_RENDERED_CONFIG="$fixture/state/runtime/vpn.conf" \
  GLUETUN_CONTROL_API_KEY_FILE="$fixture/private/control-api-key" \
  GLUETUN_CONTROL_AUTH_CONFIG_FILEPATH="$fixture/private/control-auth.toml" \
  GLUETUN_CONTROL_DEFAULT_ROLE_FILE="$fixture/private/control-default-role.json" \
  OPENVPN_USER_SECRETFILE="$fixture/private/openvpn-user" \
  OPENVPN_PASSWORD_SECRETFILE="$fixture/private/openvpn-password" \
  HTTPPROXY_USER_SECRETFILE="$fixture/private/httpproxy-user" \
  HTTPPROXY_PASSWORD_SECRETFILE="$fixture/private/httpproxy-password" \
  SHADOWSOCKS_PASSWORD_SECRETFILE="$fixture/private/shadowsocks-password" \
  DDNS_HOSTNAME=vpn.example.test \
  DDNS_POLL_SECONDS=10 DDNS_INIT_RETRY_SECONDS=1 DDNS_INIT_TIMEOUT_SECONDS=30 \
  OPENVPN_USER_CONFIGURED=1 OPENVPN_PASSWORD_CONFIGURED=1 \
  PROXY_BIND_ADDRESS="$bind_address" \
  HTTPPROXY_ENABLED=on HTTPPROXY_USER_CONFIGURED=1 HTTPPROXY_PASSWORD_CONFIGURED=1 \
  SOCKS5_USER_CONFIGURED=0 SOCKS5_PASSWORD_CONFIGURED=0 \
  SHADOWSOCKS_ENABLED=on SHADOWSOCKS_PASSWORD_CONFIGURED="$shadow_configured" \
  GLUETUN_HEALTH_TIMEOUT_SECONDS=10 \
  sh "$subject" validate
}
if validate_public 0 1 >/dev/null 2>&1; then
  fail 'non-loopback proxy bind must fail closed'
fi
if validate_public 127.0.0.1 0 >/dev/null 2>&1; then
  fail 'enabled Shadowsocks without a password file must fail closed'
fi
validate_public 127.0.0.1 1 >/dev/null
printf 'ok - proxy listeners are loopback-only and require staged secrets\n'
