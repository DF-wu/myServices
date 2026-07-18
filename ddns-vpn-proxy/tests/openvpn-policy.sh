#!/bin/sh
set -eu

# Negative tests for the deliberately narrow OpenVPN profile grammar. No Docker
# command is invoked and no host profile is modified.

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
subject=$repo_root/scripts/ddns-openvpn.sh
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
printf '%064d\n' 0 >"$workdir/control-api-key"
printf '%s\n' '[[roles]]' 'name = "ddns-watcher"' 'auth = "apikey"' \
  'apikey = "0000000000000000000000000000000000000000000000000000000000000000"' \
  'routes = ["PUT /v1/vpn/status"]' >"$workdir/control-auth.toml"
printf '%s\n' '{"name":"deny-default","auth":"apikey","apikey":"0000000000000000000000000000000000000000000000000000000000000001"}' \
  >"$workdir/control-default-role.json"
printf '%s\n' fixture-user >"$workdir/openvpn-user"
printf '%s\n' fixture-password >"$workdir/openvpn-password"
printf '%s\n' proxy-user >"$workdir/httpproxy-user"
printf '%s\n' proxy-password >"$workdir/httpproxy-password"
printf '%s\n' shadowsocks-password >"$workdir/shadowsocks-password"
chmod 400 "$workdir/control-api-key" "$workdir/control-auth.toml" "$workdir/control-default-role.json"
chmod 400 "$workdir/openvpn-user" "$workdir/openvpn-password" "$workdir/httpproxy-user" \
  "$workdir/httpproxy-password" "$workdir/shadowsocks-password"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

cat >"$workdir/safe.ovpn" <<'EOF'
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

validate() {
  profile=$1
  profile_hash_line=$(sha256sum "$profile") || return 1
  profile_hash=${profile_hash_line%% *}
  STATE_DIR="$workdir/state" \
  VPN_TYPE=openvpn \
  VPN_SOURCE_CONFIG="$profile" \
  VPN_SOURCE_SHA256="$profile_hash" \
  VPN_RENDERED_CONFIG="$workdir/state/runtime/vpn.conf" \
  GLUETUN_CONTROL_API_KEY_FILE="$workdir/control-api-key" \
  GLUETUN_CONTROL_AUTH_CONFIG_FILEPATH="$workdir/control-auth.toml" \
  GLUETUN_CONTROL_DEFAULT_ROLE_FILE="$workdir/control-default-role.json" \
  OPENVPN_USER_SECRETFILE="$workdir/openvpn-user" \
  OPENVPN_PASSWORD_SECRETFILE="$workdir/openvpn-password" \
  HTTPPROXY_USER_SECRETFILE="$workdir/httpproxy-user" \
  HTTPPROXY_PASSWORD_SECRETFILE="$workdir/httpproxy-password" \
  SHADOWSOCKS_PASSWORD_SECRETFILE="$workdir/shadowsocks-password" \
  DDNS_HOSTNAME=vpn.example.test \
  DDNS_POLL_SECONDS=10 \
  DDNS_INIT_RETRY_SECONDS=1 \
  PROXY_BIND_ADDRESS=127.0.0.1 \
  OPENVPN_USER_CONFIGURED=1 OPENVPN_PASSWORD_CONFIGURED=1 \
  HTTPPROXY_ENABLED=off \
  SOCKS5_USER_CONFIGURED=0 SOCKS5_PASSWORD_CONFIGURED=0 \
  SHADOWSOCKS_ENABLED=off \
  GLUETUN_CONTAINER_NAME=gluetun-test \
  VPROXY_CONTAINER_NAME=vproxy-test \
    GLUETUN_HEALTH_TIMEOUT_SECONDS=10 \
  sh "$subject" validate
}

validate "$workdir/safe.ovpn" >/dev/null || fail 'reviewed OpenVPN grammar should validate'
printf 'ok - reviewed OpenVPN grammar is accepted\n'

if VPN_SOURCE_SHA256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff \
  STATE_DIR="$workdir/state" VPN_TYPE=openvpn \
  VPN_SOURCE_CONFIG="$workdir/safe.ovpn" \
  VPN_RENDERED_CONFIG="$workdir/state/runtime/vpn.conf" \
  sh "$subject" validate >/dev/null 2>&1; then
  fail 'profile differing from VPN_SOURCE_SHA256 was accepted'
fi
printf 'ok - runtime profile digest mismatch is rejected\n'

for directive in \
  plugin up down route-up route-pre-down ipchange client-connect client-disconnect \
  learn-address auth-user-pass-verify tls-verify script-security config include management \
  management-client-user management-client-group setenv chroot daemon log-append writepid
do
  cp -- "$workdir/safe.ovpn" "$workdir/bad.ovpn"
  printf '%s /tmp/unsafe-hook\n' "$directive" >>"$workdir/bad.ovpn"
  if validate "$workdir/bad.ovpn" >/dev/null 2>&1; then
    fail "forbidden OpenVPN directive was accepted: $directive"
  fi
done
printf 'ok - executable/include/management directives are rejected\n'

cp -- "$workdir/safe.ovpn" "$workdir/bad-auth.ovpn"
printf '%s\n' 'auth-user-pass /tmp/credentials' >>"$workdir/bad-auth.ovpn"
if validate "$workdir/bad-auth.ovpn" >/dev/null 2>&1; then
  fail 'external auth-user-pass file was accepted'
fi
printf 'ok - external OpenVPN credential file is rejected\n'

cp -- "$workdir/safe.ovpn" "$workdir/bad-inline.ovpn"
printf '%s\n' '<connection>' 'remote evil.example 443 tcp' '</connection>' >>"$workdir/bad-inline.ovpn"
if validate "$workdir/bad-inline.ovpn" >/dev/null 2>&1; then
  fail 'unsupported inline OpenVPN block was accepted'
fi
printf 'ok - unsupported inline blocks are rejected\n'

sed 's/^remote-cert-tls server$/remote-cert-tls client/' \
  "$workdir/safe.ovpn" >"$workdir/bad-peer-role.ovpn"
if validate "$workdir/bad-peer-role.ovpn" >/dev/null 2>&1; then
  fail 'remote-cert-tls client was accepted'
fi
printf 'ok - server certificate role is enforced\n'

for weak_change in \
  's/^cipher AES-256-CBC$/cipher none/' \
  's/^auth SHA512$/auth none/' \
  's/^dev tun$/dev null/' \
  's/^verb 3$/verb 9/'
do
  sed "$weak_change" "$workdir/safe.ovpn" >"$workdir/bad-value.ovpn"
  if validate "$workdir/bad-value.ovpn" >/dev/null 2>&1; then
    fail "unsafe OpenVPN directive value was accepted: $weak_change"
  fi
done
printf 'ok - cipher, packet auth, device and verbosity values are exact-pinned\n'

cp -- "$workdir/safe.ovpn" "$workdir/duplicate-cipher.ovpn"
printf '%s\n' 'cipher AES-256-CBC' >>"$workdir/duplicate-cipher.ovpn"
if validate "$workdir/duplicate-cipher.ovpn" >/dev/null 2>&1; then
  fail 'duplicate cipher directive was accepted'
fi
printf 'ok - every reviewed OpenVPN directive is single-instance\n'

sed '/^auth-user-pass$/d' "$workdir/safe.ovpn" >"$workdir/missing-auth.ovpn"
if validate "$workdir/missing-auth.ovpn" >/dev/null 2>&1; then
  fail 'profile without the reviewed auth-user-pass directive was accepted'
fi
printf 'ok - exactly one auth-user-pass directive is required\n'

ln -s -- "$workdir/safe.ovpn" "$workdir/profile-link.ovpn"
if validate "$workdir/profile-link.ovpn" >/dev/null 2>&1; then
  fail 'symlinked OpenVPN profile was accepted'
fi
printf 'ok - symlinked profiles are rejected\n'
