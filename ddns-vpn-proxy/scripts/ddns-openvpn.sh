#!/bin/sh
set -eu

# DDNS-to-Gluetun adapter for OpenVPN and WireGuard. This is deliberately POSIX
# shell so the repository can run it from a minimal Alpine image without
# installing packages or building a project-specific image. Docker lifecycle
# calls use only the allowlisted VPN status endpoint; the Docker CLI is absent.
#
# Based on DF-wu/ddns-openvpn-proxy commit
# 8e2523978acb19e3f8aec7485db6de932918b76b. The deployment-local extension
# validates the legacy Shadowsocks exposure retained for myServices compatibility.

state_dir=${STATE_DIR:-/state}
vpn_type=${VPN_TYPE:-openvpn}
source_config=${VPN_SOURCE_CONFIG:-${OPENVPN_SOURCE_CONFIG:-/source/client.ovpn}}
source_config_sha256=${VPN_SOURCE_SHA256:-}
rendered_config=${VPN_RENDERED_CONFIG:-${OPENVPN_RENDERED_CONFIG:-$state_dir/runtime/vpn.conf}}
last_ip_file=$state_dir/ddns/last-ip
source_hash_file=$state_dir/ddns/source.sha256
heartbeat_file=$state_dir/ddns/watcher-heartbeat
poll_seconds=${DDNS_POLL_SECONDS:-60}
retry_seconds=${DDNS_INIT_RETRY_SECONDS:-5}
init_timeout=${DDNS_INIT_TIMEOUT_SECONDS:-120}
health_timeout=${GLUETUN_HEALTH_TIMEOUT_SECONDS:-120}
gluetun_health_url=${GLUETUN_HEALTHCHECK_URL:-http://gluetun:9999}
gluetun_control_host=gluetun
gluetun_control_port=8000
control_api_key_file=${GLUETUN_CONTROL_API_KEY_FILE:-/run/ddns-private/control-api-key}
control_auth_file=${GLUETUN_CONTROL_AUTH_CONFIG_FILEPATH:-/run/ddns-private/control-auth.toml}
control_default_role_file=${GLUETUN_CONTROL_DEFAULT_ROLE_FILE:-/run/ddns-private/control-default-role.json}
openvpn_user_file=${OPENVPN_USER_SECRETFILE:-/run/ddns-private/openvpn-user}
openvpn_password_file=${OPENVPN_PASSWORD_SECRETFILE:-/run/ddns-private/openvpn-password}
httpproxy_user_file=${HTTPPROXY_USER_SECRETFILE:-/run/ddns-private/httpproxy-user}
httpproxy_password_file=${HTTPPROXY_PASSWORD_SECRETFILE:-/run/ddns-private/httpproxy-password}
socks5_user_file=${SOCKS5_USER_SECRETFILE:-/run/ddns-private/socks5-user}
socks5_password_file=${SOCKS5_PASSWORD_SECRETFILE:-/run/ddns-private/socks5-password}
shadowsocks_password_file=${SHADOWSOCKS_PASSWORD_SECRETFILE:-/run/ddns-private/shadowsocks-password}

remote_source_host=
ddns_hostname=

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log() {
  level=$1
  shift
  printf '%s level=%s %s\n' "$(timestamp)" "$level" "$*"
}

die() {
  log ERROR "$*" >&2
  exit 64
}

is_uint() {
  case $1 in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 { exit 1 }
    {
      for (i = 1; i <= 4; i++) {
        if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255 ||
            (length($i) > 1 && substr($i, 1, 1) == "0")) exit 1
      }
    }
  '
}

validate_hostname() {
  hostname=$1
  case $hostname in
    ''|.*|*.|*..*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#hostname}" -le 253 ] || return 1
  return 0
}

validate_configured_pair() {
  pair_name=$1
  user_configured=${2:-0}
  password_configured=${3:-0}
  case $user_configured:$password_configured in
    0:0|1:1) ;;
    *) die "$pair_name user and password must both be set or both be empty" ;;
  esac
}

validate_control_api_key() {
  [ -f "$control_api_key_file" ] ||
    die "Gluetun control API key file not found: $control_api_key_file"
  [ ! -L "$control_api_key_file" ] ||
    die "Gluetun control API key file must not be a symlink: $control_api_key_file"
  [ -r "$control_api_key_file" ] && [ -s "$control_api_key_file" ] ||
    die "Gluetun control API key file is empty or unreadable: $control_api_key_file"
  [ "$(stat -c '%a' "$control_api_key_file")" = 400 ] ||
    die "Gluetun control API key file must be mode 0400: $control_api_key_file"
  control_key_lines=$(wc -l <"$control_api_key_file") ||
    die "failed to inspect Gluetun control API key file"
  [ "$control_key_lines" -eq 1 ] ||
    die "Gluetun control API key file must contain exactly one line"
  control_key_bytes=$(wc -c <"$control_api_key_file") ||
    die "failed to size Gluetun control API key file"
  [ "$control_key_bytes" -eq 65 ] ||
    die "Gluetun control API key file must contain exactly 64 characters and one newline"
  control_api_key=$(sed -n '1p' "$control_api_key_file") ||
    die "failed to read Gluetun control API key"
  case $control_api_key in
    *[!0-9a-f]*|'') die "Gluetun control API key must be lowercase hexadecimal" ;;
  esac
  [ "${#control_api_key}" -eq 64 ] ||
    die "Gluetun control API key must contain exactly 64 hexadecimal characters"
}

validate_secret_file() {
  secret_name=$1
  secret_file=$2
  [ -f "$secret_file" ] ||
    die "$secret_name secret file not found: $secret_file"
  [ ! -L "$secret_file" ] ||
    die "$secret_name secret file must not be a symlink: $secret_file"
  [ -r "$secret_file" ] && [ -s "$secret_file" ] ||
    die "$secret_name secret file is empty or unreadable: $secret_file"
  [ "$(stat -c '%a' "$secret_file")" = 400 ] ||
    die "$secret_name secret file must be mode 0400: $secret_file"
  secret_lines=$(wc -l <"$secret_file") ||
    die "failed to inspect $secret_name secret file"
  [ "$secret_lines" -eq 1 ] ||
    die "$secret_name secret file must contain exactly one line"
  secret_bytes=$(wc -c <"$secret_file") ||
    die "failed to size $secret_name secret file"
  [ "$secret_bytes" -le 4097 ] ||
    die "$secret_name secret file is too long"
  secret_value=$(sed -n '1p' "$secret_file") ||
    die "failed to read $secret_name secret file"
  [ -n "$secret_value" ] ||
    die "$secret_name secret file is empty"
  [ -z "$(sed -n '2,$p' "$secret_file")" ] ||
    die "$secret_name secret file contains trailing data"
  printf '%s\n' "$secret_value" | LC_ALL=C awk '/[[:cntrl:]]/ { found=1 } END { exit(found ? 1 : 0) }' ||
    die "$secret_name secret file contains control characters"
}

validate_control_auth() {
  [ -f "$control_auth_file" ] && [ ! -L "$control_auth_file" ] ||
    die "Gluetun control auth file is missing or symlinked: $control_auth_file"
  [ "$(stat -c '%a' "$control_auth_file")" = 400 ] ||
    die "Gluetun control auth file must be mode 0400: $control_auth_file"
  expected_auth=$(mktemp /tmp/ddns-control-auth.XXXXXX) ||
    die 'failed to create control auth verification file'
  if ! {
    printf '%s\n' '[[roles]]'
    printf '%s\n' 'name = "ddns-watcher"'
    printf '%s\n' 'auth = "apikey"'
    printf 'apikey = "%s"\n' "$control_api_key"
    printf '%s\n' 'routes = ["PUT /v1/vpn/status"]'
  } >"$expected_auth"; then
    rm -f "$expected_auth" || :
    die 'failed to render expected control auth'
  fi
  if ! cmp -s "$expected_auth" "$control_auth_file"; then
    rm -f "$expected_auth" || :
    die 'Gluetun control auth does not match the private API key and status-only role'
  fi
  rm -f "$expected_auth" || die 'failed to remove control auth verification file'
}

validate_control_default_role() {
  [ -f "$control_default_role_file" ] && [ ! -L "$control_default_role_file" ] ||
    die "Gluetun default control role is missing or symlinked: $control_default_role_file"
  [ "$(stat -c '%a' "$control_default_role_file")" = 400 ] ||
    die "Gluetun default control role must be mode 0400: $control_default_role_file"
  role_lines=$(wc -l <"$control_default_role_file") ||
    die 'failed to inspect Gluetun default control role'
  [ "$role_lines" -eq 1 ] || die 'Gluetun default control role must contain one line'
  role_json=$(sed -n '1p' "$control_default_role_file") ||
    die 'failed to read Gluetun default control role'
  printf '%s\n' "$role_json" |
    grep -Eq '^\{"name":"deny-default","auth":"apikey","apikey":"[0-9a-f]{64}"\}$' ||
    die 'Gluetun default control role is not the reviewed deny role'
  default_role_key=$(printf '%s\n' "$role_json" | sed 's/^.*"apikey":"//; s/"}$//')
  [ "$default_role_key" != "$control_api_key" ] ||
    die 'Gluetun default role key must be distinct from watcher key'
}

validate_control_files() {
  validate_control_api_key
  validate_control_auth
  validate_control_default_role
}

validate_secret_pair() {
  pair_name=$1
  user_configured=$2
  password_configured=$3
  user_file=$4
  password_file=$5
  case $user_configured:$password_configured in
    0:0) ;;
    1:1)
      validate_secret_file "$pair_name user" "$user_file"
      validate_secret_file "$pair_name password" "$password_file"
      ;;
    *) die "$pair_name user and password configuration is inconsistent" ;;
  esac
}

validate_secret_files() {
  validate_secret_pair OPENVPN \
    "${OPENVPN_USER_CONFIGURED:-0}" "${OPENVPN_PASSWORD_CONFIGURED:-0}" \
    "$openvpn_user_file" "$openvpn_password_file"
  validate_secret_pair HTTPPROXY \
    "${HTTPPROXY_USER_CONFIGURED:-0}" "${HTTPPROXY_PASSWORD_CONFIGURED:-0}" \
    "$httpproxy_user_file" "$httpproxy_password_file"
  validate_secret_pair SOCKS5 \
    "${SOCKS5_USER_CONFIGURED:-0}" "${SOCKS5_PASSWORD_CONFIGURED:-0}" \
    "$socks5_user_file" "$socks5_password_file"
  if [ "${SHADOWSOCKS_ENABLED:-off}" = on ]; then
    [ "${SHADOWSOCKS_PASSWORD_CONFIGURED:-0}" = 1 ] ||
      die 'Shadowsocks password must be configured when Shadowsocks is enabled'
    validate_secret_file 'Shadowsocks password' "$shadowsocks_password_file"
  fi
}

validate_relative_references() {
  source_parent=$(dirname "$source_config") || return 1
  tab=$(printf '\t') || return 1

  awk '
    /^[[:space:]]*[#;]/ { next }
    $1 ~ /^(ca|cert|key|tls-auth|tls-crypt|tls-crypt-v2|crl-verify|dh|pkcs12|secret|askpass|http-proxy-user-pass)$/ && NF >= 2 {
      print $1 "\t" $2
    }
  ' "$source_config" |
  while IFS="$tab" read -r directive reference; do
    case $reference in
      *\"*|*\'*)
        die "$directive uses a quoted path; paths containing whitespace are not supported: $reference"
        ;;
      stdin) ;;
      /*)
        [ -r "$reference" ] || die "$directive references an unreadable file: $reference"
        ;;
      *)
        [ -r "$source_parent/$reference" ] ||
          die "$directive references an unreadable file: $source_parent/$reference"
        ;;
    esac
  done
}

validate_source_file() {
  profile_name=$1
  [ -f "$source_config" ] || die "$profile_name profile not found: $source_config"
  [ ! -L "$source_config" ] || die "$profile_name profile must not be a symlink: $source_config"
  [ -r "$source_config" ] || die "$profile_name profile is not readable: $source_config"
  [ -s "$source_config" ] || die "$profile_name profile is empty: $source_config"
}

validate_source_sha256() {
  case $source_config_sha256 in
    ''|*[!0-9a-f]*)
      die 'VPN_SOURCE_SHA256 must be a 64-character lowercase hexadecimal digest'
      ;;
  esac
  [ "${#source_config_sha256}" -eq 64 ] ||
    die 'VPN_SOURCE_SHA256 must be a 64-character lowercase hexadecimal digest'
  source_digest_line=$(sha256sum "$source_config") ||
    die "failed to hash reviewed VPN source profile: $source_config"
  source_digest=${source_digest_line%% *}
  [ "$source_digest" = "$source_config_sha256" ] ||
    die "VPN source profile does not match VPN_SOURCE_SHA256: $source_config"
}

validate_openvpn_directives() {
  # This deployment intentionally supports only the reviewed Surfshark client
  # profile shape. A strict allowlist prevents OpenVPN hooks, plugins, config
  # includes, management listeners and arbitrary host-file references from being
  # smuggled into a profile that Gluetun later executes as root.
  awk '
    function invalid(message) {
      print "OpenVPN profile " message > "/dev/stderr"
      failed = 1
    }

    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
    }

    inline != "" {
      if (line == "</" inline ">") {
        if (inline_lines == 0) invalid("has an empty inline <" inline "> block")
        inline = ""
        inline_lines = 0
      } else if (line != "") {
        inline_lines++
      }
      next
    }

    line == "" || line ~ /^[#;]/ { next }

    line == "<ca>" {
      ca_count++
      inline = "ca"
      next
    }

    line == "<tls-auth>" {
      tls_auth_count++
      inline = "tls-auth"
      next
    }

    $1 == "client" {
      client_count++
      if (NF != 1) invalid("client must not have arguments")
      next
    }

    $1 == "dev" {
      dev_count++
      if (NF != 2 || $2 != "tun") invalid("dev must be exactly: dev tun")
      next
    }

    $1 == "proto" {
      proto_count++
      if (NF != 2 || $2 != "udp") invalid("proto must be exactly: proto udp")
      next
    }

    $1 == "remote" {
      remote_count++
      if (NF != 3 || $3 != "1194") {
        invalid("remote must be exactly: remote HOST 1194")
      }
      next
    }

    $1 == "remote-random" {
      remote_random_count++
      if (NF != 1) invalid("remote-random must not have arguments")
      next
    }

    $1 == "nobind" {
      nobind_count++
      if (NF != 1) invalid("nobind must not have arguments")
      next
    }

    $1 == "tun-mtu" {
      tun_mtu_count++
      if (NF != 2 || $2 != "1500") invalid("tun-mtu must be exactly: tun-mtu 1500")
      next
    }

    $1 == "mssfix" {
      mssfix_count++
      if (NF != 2 || $2 != "1450") invalid("mssfix must be exactly: mssfix 1450")
      next
    }

    $1 == "ping" {
      ping_count++
      if (NF != 2 || $2 != "15") invalid("ping must be exactly: ping 15")
      next
    }

    $1 == "ping-restart" {
      ping_restart_count++
      if (NF != 2 || $2 != "0") invalid("ping-restart must be exactly: ping-restart 0")
      next
    }

    $1 == "reneg-sec" {
      reneg_sec_count++
      if (NF != 2 || $2 != "0") invalid("reneg-sec must be exactly: reneg-sec 0")
      next
    }

    $1 == "auth-user-pass" {
      auth_user_pass_count++
      if (NF != 1) invalid("auth-user-pass must not reference an external file")
      next
    }

    $1 == "remote-cert-tls" {
      remote_cert_tls_count++
      if (NF != 2 || $2 != "server") {
        invalid("remote-cert-tls must be exactly: remote-cert-tls server")
      }
      next
    }

    $1 == "verb" {
      verb_count++
      if (NF != 2 || $2 != "3") invalid("verb must be exactly: verb 3")
      next
    }

    $1 == "fast-io" {
      fast_io_count++
      if (NF != 1) invalid("fast-io must not have arguments")
      next
    }

    $1 == "cipher" {
      cipher_count++
      if (NF != 2 || $2 != "AES-256-CBC") {
        invalid("cipher must be exactly: cipher AES-256-CBC")
      }
      next
    }

    $1 == "auth" {
      auth_count++
      if (NF != 2 || $2 != "SHA512") invalid("auth must be exactly: auth SHA512")
      next
    }

    $1 == "key-direction" {
      key_direction_count++
      if (NF != 2 || $2 != "1") {
        invalid("key-direction must be exactly: key-direction 1")
      }
      next
    }

    { invalid("contains forbidden or unsupported directive: " $1) }

    END {
      if (inline != "") invalid("has an unterminated inline <" inline "> block")
      if (ca_count != 1) invalid("must contain exactly one inline <ca> block")
      if (tls_auth_count != 1) invalid("must contain exactly one inline <tls-auth> block")
      if (client_count != 1) invalid("must contain exactly one client directive")
      if (dev_count != 1) invalid("must contain exactly one dev directive")
      if (proto_count != 1) invalid("must contain exactly one proto directive")
      if (remote_count != 1) invalid("must contain exactly one remote directive")
      if (remote_random_count != 1) invalid("must contain exactly one remote-random directive")
      if (nobind_count != 1) invalid("must contain exactly one nobind directive")
      if (tun_mtu_count != 1) invalid("must contain exactly one tun-mtu directive")
      if (mssfix_count != 1) invalid("must contain exactly one mssfix directive")
      if (ping_count != 1) invalid("must contain exactly one ping directive")
      if (ping_restart_count != 1) invalid("must contain exactly one ping-restart directive")
      if (reneg_sec_count != 1) invalid("must contain exactly one reneg-sec directive")
      if (remote_cert_tls_count != 1) invalid("must contain exactly one remote-cert-tls directive")
      if (auth_user_pass_count != 1) invalid("must contain exactly one auth-user-pass directive")
      if (verb_count != 1) invalid("must contain exactly one verb directive")
      if (fast_io_count != 1) invalid("must contain exactly one fast-io directive")
      if (cipher_count != 1) invalid("must contain exactly one cipher directive")
      if (auth_count != 1) invalid("must contain exactly one auth directive")
      if (key_direction_count != 1) invalid("must contain exactly one key-direction directive")
      if (failed) exit 1
    }
  ' "$source_config" || die "OpenVPN profile contains unsafe or unsupported directives: $source_config"
}

validate_openvpn_config() {
  validate_source_file OpenVPN
  validate_source_sha256
  validate_openvpn_directives

  remote_count=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "remote" { count++ }
    END { print count + 0 }
  ' "$source_config")
  [ "$remote_count" -eq 1 ] ||
    die "expected exactly one active remote directive in $source_config, found $remote_count"

  remote_source_host=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "remote" { print $2; exit }
  ' "$source_config")

  remote_fields=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "remote" {
      fields = NF
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[#;]/) {
          fields = i - 1
          break
        }
      }
      print fields
      exit
    }
  ' "$source_config")
  if ! { [ "$remote_fields" -eq 3 ] || [ "$remote_fields" -eq 4 ]; }; then
    die "remote must be: remote HOST PORT [PROTO]"
  fi

  remote_port=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "remote" { if (NF >= 3 && $3 !~ /^[#;]/) print $3; exit }
  ' "$source_config")
  [ -n "$remote_port" ] || die "remote port must be explicitly configured"
  is_uint "$remote_port" || die "remote port is not numeric: $remote_port"
  if ! { [ "$remote_port" -ge 1 ] && [ "$remote_port" -le 65535 ]; }; then
    die "remote port must be between 1 and 65535: $remote_port"
  fi

  remote_protocol=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "remote" { if (NF >= 4 && $4 !~ /^[#;]/) print $4; exit }
  ' "$source_config")
  proto_count=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "proto" { count++ }
    END { print count + 0 }
  ' "$source_config")
  [ "$proto_count" -eq 1 ] ||
    die "OpenVPN profile must contain exactly one active proto directive"
  profile_protocol=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "proto" { print $2; exit }
  ' "$source_config")
  case $profile_protocol in
    udp|tcp) ;;
    *) die "profile proto must be udp or tcp: $profile_protocol" ;;
  esac
  if [ -n "$remote_protocol" ] && [ "$remote_protocol" != "$profile_protocol" ]; then
    die "remote protocol and profile proto must match"
  fi
  remote_protocol=$profile_protocol

  auth_user_pass_count=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "auth-user-pass" { count++ }
    END { print count + 0 }
  ' "$source_config")
  if [ "$auth_user_pass_count" -gt 0 ]; then
    if ! { [ "${OPENVPN_USER_CONFIGURED:-0}" = 1 ] &&
      [ "${OPENVPN_PASSWORD_CONFIGURED:-0}" = 1 ]; }; then
      die "profile uses auth-user-pass; stage both OpenVPN credential files"
    fi
  fi

  validate_relative_references
}

validate_wireguard_config() {
  validate_source_file WireGuard

  wireguard_endpoint=$(awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    function invalid(message) {
      print "WireGuard profile " message > "/dev/stderr"
      failed = 1
    }

    /^[[:space:]]*([#;]|$)/ { next }

    /^[[:space:]]*\[/ {
      heading = trim($0)
      if (heading == "[Interface]") {
        section = "interface"
        interface_count++
      } else if (heading == "[Peer]") {
        section = "peer"
        peer_count++
      } else {
        section = "other"
      }
      next
    }

    {
      line = $0
      sub(/[[:space:]]+[#;].*$/, "", line)
      separator = index(line, "=")
      if (separator == 0) next
      key = trim(substr(line, 1, separator - 1))
      value = trim(substr(line, separator + 1))

      if (section == "interface" && key == "PrivateKey") {
        private_key_count++
        if (value == "") invalid("has an empty Interface PrivateKey")
      } else if (section == "interface" && key == "Address") {
        address_count++
        if (value == "") invalid("has an empty Interface Address")
      } else if (section == "peer" && key == "PublicKey") {
        public_key_count++
        if (value == "") invalid("has an empty Peer PublicKey")
      } else if (section == "peer" && key == "Endpoint") {
        endpoint_count++
        endpoint = value
      }
    }

    END {
      if (interface_count != 1) invalid("must contain exactly one [Interface] section")
      if (peer_count != 1) invalid("must contain exactly one [Peer] section")
      if (private_key_count != 1) invalid("must contain exactly one Interface PrivateKey")
      if (address_count != 1) invalid("must contain exactly one Interface Address")
      if (public_key_count != 1) invalid("must contain exactly one Peer PublicKey")
      if (endpoint_count != 1) invalid("must contain exactly one Peer Endpoint")
      if (failed) exit 1
      print endpoint
    }
  ' "$source_config") || die "invalid WireGuard profile: $source_config"

  case $wireguard_endpoint in
    *:*:*) die "WireGuard Endpoint must use a hostname and one port: $wireguard_endpoint" ;;
    *:*) ;;
    *) die "WireGuard Endpoint must be HOST:PORT: $wireguard_endpoint" ;;
  esac

  remote_source_host=${wireguard_endpoint%:*}
  remote_port=${wireguard_endpoint##*:}
  validate_hostname "$remote_source_host" ||
    die "invalid WireGuard Endpoint hostname: $remote_source_host"
  is_uint "$remote_port" || die "WireGuard Endpoint port is not numeric: $remote_port"
  if ! { [ "$remote_port" -ge 1 ] && [ "$remote_port" -le 65535 ]; }; then
    die "WireGuard Endpoint port must be between 1 and 65535: $remote_port"
  fi
}

validate_common_environment() {
  validate_configured_pair OPENVPN \
    "${OPENVPN_USER_CONFIGURED:-0}" "${OPENVPN_PASSWORD_CONFIGURED:-0}"
  validate_configured_pair HTTPPROXY \
    "${HTTPPROXY_USER_CONFIGURED:-0}" "${HTTPPROXY_PASSWORD_CONFIGURED:-0}"
  validate_configured_pair SOCKS5 \
    "${SOCKS5_USER_CONFIGURED:-0}" "${SOCKS5_PASSWORD_CONFIGURED:-0}"

  case ${HTTPPROXY_ENABLED:-on} in
    on|off) ;;
    *) die "HTTPPROXY must be on or off" ;;
  esac

  case ${SHADOWSOCKS_ENABLED:-off} in
    on|off) ;;
    *) die "SHADOWSOCKS must be on or off" ;;
  esac

  [ "${PROXY_BIND_ADDRESS:-127.0.0.1}" = 127.0.0.1 ] ||
    die 'proxy listeners must be bound to 127.0.0.1; use an authenticated tunnel for remote access'

  ddns_hostname=${DDNS_HOSTNAME:-$remote_source_host}
  validate_hostname "$ddns_hostname" || die "invalid DDNS hostname: $ddns_hostname"
  if is_ipv4 "$ddns_hostname"; then
    die "DDNS target must be a hostname, not an IPv4 address: $ddns_hostname"
  fi

  if [ -n "${DDNS_RESOLVER:-}" ]; then
    is_ipv4 "$DDNS_RESOLVER" || die "DDNS_RESOLVER must be an IPv4 address: $DDNS_RESOLVER"
  fi

  if [ -n "${DDNS_OVERRIDE_IPS:-}" ]; then
    override_tokens=$(printf '%s\n' "$DDNS_OVERRIDE_IPS" |
      tr ',' '\n' | awk '{ for (i = 1; i <= NF; i++) print $i }')
    [ -n "$override_tokens" ] || die "DDNS_OVERRIDE_IPS contains no addresses"
    override_valid=$(printf '%s\n' "$override_tokens" | filter_ipv4s)
    [ "$(printf '%s\n' "$override_tokens" | sort -u)" = "$override_valid" ] ||
      die "DDNS_OVERRIDE_IPS contains an invalid IPv4 address"
  fi

  if ! { is_uint "$poll_seconds" && [ "$poll_seconds" -ge 10 ]; }; then
    die "DDNS_POLL_SECONDS must be an integer of at least 10"
  fi
  if ! { is_uint "$retry_seconds" && [ "$retry_seconds" -ge 1 ]; }; then
    die "DDNS_INIT_RETRY_SECONDS must be a positive integer"
  fi
  if ! { is_uint "$init_timeout" && [ "$init_timeout" -ge 30 ] &&
    [ "$init_timeout" -le 600 ]; }; then
    die "DDNS_INIT_TIMEOUT_SECONDS must be an integer between 30 and 600"
  fi
  if ! { is_uint "$health_timeout" && [ "$health_timeout" -ge 10 ] &&
    [ "$health_timeout" -le 300 ]; }; then
    die "GLUETUN_HEALTH_TIMEOUT_SECONDS must be an integer between 10 and 300"
  fi
}

validate_config() {
  case $vpn_type in
    openvpn) validate_openvpn_config ;;
    *) die "this deployment supports only VPN_TYPE=openvpn: $vpn_type" ;;
  esac
  validate_common_environment
}

filter_ipv4s() {
  awk -F. '
    NF == 4 {
      valid = 1
      for (i = 1; i <= 4; i++) {
        if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255 ||
            (length($i) > 1 && substr($i, 1, 1) == "0")) valid = 0
      }
      if (valid) print $0
    }
  ' | sort -u
}

resolve_ipv4s() {
  if [ -n "${DDNS_OVERRIDE_IPS:-}" ]; then
    printf '%s\n' "$DDNS_OVERRIDE_IPS" | tr ',' '\n' |
      awk '{ for (i = 1; i <= NF; i++) print $i }' | filter_ipv4s
    return
  fi

  if [ -n "${DDNS_RESOLVER:-}" ]; then
    nslookup "$ddns_hostname" "$DDNS_RESOLVER" 2>/dev/null |
      awk '
        /^Name:[[:space:]]/ { answers = 1; next }
        answers && /^Address([[:space:]][0-9]+)?:[[:space:]]/ {
          sub(/^Address([[:space:]][0-9]+)?:[[:space:]]*/, "")
          print
        }
      ' | filter_ipv4s
    return
  fi

  nslookup "$ddns_hostname" 2>/dev/null |
    awk '
      /^Name:[[:space:]]/ { answers = 1; next }
      answers && /^Address([[:space:]][0-9]+)?:[[:space:]]/ {
        sub(/^Address([[:space:]][0-9]+)?:[[:space:]]*/, "")
        print
      }
    ' | filter_ipv4s
}

read_state() {
  file=$1
  [ -r "$file" ] || return 1
  sed -n '1p' "$file"
}

read_optional_state() {
  file=$1
  [ -e "$file" ] || return 0
  read_state "$file"
}

write_state() {
  value=$1
  destination=$2
  directory=$(dirname "$destination") || return 1
  mkdir -p "$directory" || return 1
  temporary=$(mktemp "$directory/.tmp.XXXXXX") || return 1

  if ! printf '%s\n' "$value" > "$temporary"; then
    rm -f "$temporary" || :
    return 1
  fi
  if ! chmod 600 "$temporary"; then
    rm -f "$temporary" || :
    return 1
  fi
  if ! mv -f "$temporary" "$destination"; then
    rm -f "$temporary" || :
    return 1
  fi
}

source_hash() {
  validate_source_sha256 || return 1
  if [ "$vpn_type" = wireguard ]; then
    hash_line=$(sha256sum "$source_config") || return 1
    hash_value=${hash_line%% *}
    [ -n "$hash_value" ] || return 1
    printf '%s\n' "$hash_value"
    return 0
  fi

  source_parent=$(dirname "$source_config")
  tab=$(printf '\t')
  hash_input=$(mktemp /tmp/ddns-source-hash.XXXXXX) || return 1
  hash_references=$(mktemp /tmp/ddns-source-refs.XXXXXX) || {
    rm -f "$hash_input" || :
    return 1
  }

  if ! sha256sum "$source_config" > "$hash_input"; then
    rm -f "$hash_input" "$hash_references" || :
    return 1
  fi
  if ! awk '
    /^[[:space:]]*[#;]/ { next }
    $1 ~ /^(ca|cert|key|tls-auth|tls-crypt|tls-crypt-v2|crl-verify|dh|pkcs12|secret|askpass|http-proxy-user-pass)$/ && NF >= 2 {
      print $1 "\t" $2
    }
  ' "$source_config" > "$hash_references"; then
    rm -f "$hash_input" "$hash_references" || :
    return 1
  fi

  reference_hash_failed=0
  while IFS="$tab" read -r directive reference; do
    case $reference in
      '') continue ;;
      stdin) continue ;;
      /*) hash_reference=$reference ;;
      *) hash_reference=$source_parent/$reference ;;
    esac
    if ! sha256sum "$hash_reference" >> "$hash_input"; then
      reference_hash_failed=1
      break
    fi
  done < "$hash_references"
  if [ "$reference_hash_failed" = 1 ]; then
    rm -f "$hash_input" "$hash_references" || :
    return 1
  fi

  hash_line=$(sha256sum "$hash_input") || {
    rm -f "$hash_input" "$hash_references" || :
    return 1
  }
  rm -f "$hash_input" "$hash_references" || return 1
  hash_value=${hash_line%% *}
  [ -n "$hash_value" ] || return 1
  printf '%s\n' "$hash_value"
}

select_ip() {
  addresses=$1
  preferred=${2:-}

  if [ -n "$preferred" ] && printf '%s\n' "$addresses" | grep -Fxq "$preferred"; then
    printf '%s\n' "$preferred"
    return
  fi

  printf '%s\n' "$addresses" | sed -n '1p'
}

render_openvpn_config() {
  resolved_ip=$1
  output_parent=$(dirname "$rendered_config") || return 1
  source_parent=$(dirname "$source_config") || return 1
  mkdir -p "$output_parent" || return 1
  temporary=$(mktemp "$output_parent/.client.ovpn.XXXXXX") || return 1

  if ! awk -v ip="$resolved_ip" -v source_parent="$source_parent" '
    function absolute(path) {
      if (path == "" || path == "stdin" || path ~ /^\//) return path
      return source_parent "/" path
    }

    /^[[:space:]]*[#;]/ { print; next }

    $1 == "remote" {
      $2 = ip
      replaced++
      print
      next
    }

    $1 ~ /^(ca|cert|key|tls-auth|tls-crypt|tls-crypt-v2|crl-verify|dh|pkcs12|secret|askpass|http-proxy-user-pass)$/ && NF >= 2 {
      $2 = absolute($2)
    }

    { print }
    END {
      if (replaced != 1) exit 1
    }
  ' "$source_config" > "$temporary"; then
    rm -f "$temporary" || :
    return 1
  fi

  if [ ! -s "$temporary" ]; then
    rm -f "$temporary" || :
    return 1
  fi
  if ! chmod 600 "$temporary"; then
    rm -f "$temporary" || :
    return 1
  fi
  if ! mv -f "$temporary" "$rendered_config"; then
    rm -f "$temporary" || :
    return 1
  fi
}

render_wireguard_config() {
  resolved_ip=$1
  output_parent=$(dirname "$rendered_config") || return 1
  mkdir -p "$output_parent" || return 1
  temporary=$(mktemp "$output_parent/.wg0.conf.XXXXXX") || return 1

  if ! awk -v ip="$resolved_ip" '
    /^[[:space:]]*\[/ {
      section = $0
      sub(/^[[:space:]]+/, "", section)
      sub(/[[:space:]]+$/, "", section)
      print
      next
    }

    section == "[Peer]" && /^[[:space:]]*Endpoint[[:space:]]*=/ {
      match($0, /^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*/)
      prefix = substr($0, 1, RLENGTH)
      remainder = substr($0, RLENGTH + 1)
      comment = ""
      if (match(remainder, /[[:space:]]+[#;]/)) {
        comment = substr(remainder, RSTART)
        remainder = substr(remainder, 1, RSTART - 1)
      }
      sub(/^[[:space:]]+/, "", remainder)
      sub(/[[:space:]]+$/, "", remainder)
      separator = index(remainder, ":")
      port = substr(remainder, separator + 1)
      replaced++
      print prefix ip ":" port comment
      next
    }

    { print }
    END {
      if (replaced != 1) exit 1
    }
  ' "$source_config" > "$temporary"; then
    rm -f "$temporary" || :
    return 1
  fi

  if [ ! -s "$temporary" ]; then
    rm -f "$temporary" || :
    return 1
  fi
  if ! chmod 600 "$temporary"; then
    rm -f "$temporary" || :
    return 1
  fi
  if ! mv -f "$temporary" "$rendered_config"; then
    rm -f "$temporary" || :
    return 1
  fi
}

render_config() {
  resolved_ip=$1
  case $vpn_type in
    openvpn) render_openvpn_config "$resolved_ip" ;;
    wireguard) render_wireguard_config "$resolved_ip" ;;
    *) return 1 ;;
  esac
}

touch_heartbeat() {
  heartbeat=$(date -u '+%s') || return 1
  write_state "$heartbeat" "$heartbeat_file"
}

ensure_heartbeat_writable() {
  heartbeat_directory=$(dirname "$heartbeat_file") || return 1
  mkdir -p "$heartbeat_directory" || return 1
  heartbeat_probe=$(mktemp "$heartbeat_directory/.heartbeat-check.XXXXXX") || return 1
  if ! printf '%s\n' probe >"$heartbeat_probe"; then
    rm -f "$heartbeat_probe" || :
    return 1
  fi
  if ! chmod 600 "$heartbeat_probe"; then
    rm -f "$heartbeat_probe" || :
    return 1
  fi
  rm -f "$heartbeat_probe"
}

finish_watch_once() {
  if ! touch_heartbeat; then
    log ERROR "failed to commit successful watcher heartbeat file=$heartbeat_file"
    return 1
  fi
  return 0
}

resolve_and_select() {
  preferred=${1:-}
  addresses=$(resolve_ipv4s || true)
  [ -n "$addresses" ] || return 1
  select_ip "$addresses" "$preferred"
}

initialize() {
  validate_config
  validate_control_files
  log INFO "initializing vpn_type=$vpn_type hostname=$ddns_hostname profile=$source_config"

  # On the first deployment Gluetun has not started yet, so the rendered profile
  # becomes the applied state once depends_on releases it. On later Compose or
  # Portainer updates an old Gluetun may still be running: stage the new profile,
  # but preserve the old applied IP/hash so the watcher must detect and restart.
  fresh_state=1
  for existing_state in "$last_ip_file" "$source_hash_file" "$rendered_config"
  do
    if [ -e "$existing_state" ] || [ -L "$existing_state" ]; then
      fresh_state=0
    fi
  done

  init_started=$(date -u '+%s') || return 1
  init_deadline=$((init_started + init_timeout))

  while :; do
    if ! previous_ip=$(read_optional_state "$last_ip_file"); then
      log ERROR "failed to read previous DDNS state file=$last_ip_file"
      return 1
    fi
    if selected_ip=$(resolve_and_select "$previous_ip"); then
      if ! current_hash=$(source_hash); then
        log ERROR "failed to hash VPN source profile=$source_config"
        return 1
      fi
      if ! render_config "$selected_ip"; then
        log ERROR "failed to render VPN profile output=$rendered_config"
        return 1
      fi
      if ! verified_hash=$(source_hash); then
        log ERROR "failed to verify VPN source profile after render profile=$source_config"
        return 1
      fi
      if [ "$verified_hash" != "$current_hash" ]; then
        log WARN "VPN source changed during render; retrying profile=$source_config"
        sleep "$retry_seconds"
        continue
      fi
      if [ "$fresh_state" = 1 ]; then
        if ! write_state "$selected_ip" "$last_ip_file"; then
          log ERROR "failed to commit initial DDNS state file=$last_ip_file"
          return 1
        fi
        if ! write_state "$current_hash" "$source_hash_file"; then
          log ERROR "failed to commit initial source fingerprint file=$source_hash_file"
          return 1
        fi
        log INFO "rendered initial profile vpn_type=$vpn_type hostname=$ddns_hostname ip=$selected_ip output=$rendered_config"
      else
        log INFO "staged updated profile without changing applied state vpn_type=$vpn_type hostname=$ddns_hostname ip=$selected_ip output=$rendered_config"
      fi
      return 0
    fi

    log WARN "DNS lookup failed hostname=$ddns_hostname retry_in=${retry_seconds}s"
    init_now=$(date -u '+%s') || return 1
    if [ "$init_now" -ge "$init_deadline" ]; then
      log ERROR "DNS initialization timed out hostname=$ddns_hostname timeout=${init_timeout}s"
      return 1
    fi
    sleep "$retry_seconds" || return 1
  done
}

gluetun_control_put() {
  request_path=$1
  request_body=$2
  request_file=$(mktemp /tmp/gluetun-control-request.XXXXXX) || return 1
  response_file=$(mktemp /tmp/gluetun-control-response.XXXXXX) || {
    rm -f "$request_file" || :
    return 1
  }
  content_length=${#request_body}

  if ! printf 'PUT %s HTTP/1.1\r\nHost: %s\r\nX-API-Key: %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
    "$request_path" "$gluetun_control_host" "$control_api_key" \
    "$content_length" "$request_body" \
    >"$request_file"; then
    rm -f "$request_file" "$response_file" || :
    return 1
  fi
  if ! chmod 600 "$request_file" "$response_file"; then
    rm -f "$request_file" "$response_file" || :
    return 1
  fi
  if ! nc -w "$health_timeout" "$gluetun_control_host" "$gluetun_control_port" \
    <"$request_file" >"$response_file"; then
    rm -f "$request_file" "$response_file" || :
    return 1
  fi
  if ! IFS= read -r status_line <"$response_file"; then
    rm -f "$request_file" "$response_file" || :
    return 1
  fi
  if ! rm -f "$request_file" "$response_file"; then
    return 1
  fi

  case $status_line in
    "HTTP/1.1 200 "*|"HTTP/1.0 200 "*) return 0 ;;
    *) return 1 ;;
  esac
}

wait_gluetun_healthy() {
  now=$(date -u '+%s') || return 1
  deadline=$((now + health_timeout))

  while ! wget -q --spider -T 3 "$gluetun_health_url"; do
    now=$(date -u '+%s') || return 1
    [ "$now" -lt "$deadline" ] || return 1
    sleep 1 || return 1
  done
}

probe_vproxy_socks5() {
  probe_file=$(mktemp /tmp/ddns-socks-health.XXXXXX) || return 1
  if ! {
    printf '\005\001\000\005\001\000\001\177\000\000\001\047\017'
    printf 'GET / HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'
  } | nc -w 3 gluetun 1080 >"$probe_file"; then
    rm -f -- "$probe_file" || :
    return 1
  fi
  probe_prefix=$(dd if="$probe_file" bs=1 count=4 2>/dev/null |
    od -An -tx1 | tr -d ' \n') || probe_prefix=
  rm -f -- "$probe_file" || return 1
  [ "$probe_prefix" = 05000500 ]
}

wait_vproxy_ready() {
  now=$(date -u '+%s') || return 1
  deadline=$((now + health_timeout))

  while ! probe_vproxy_socks5; do
    now=$(date -u '+%s') || return 1
    [ "$now" -lt "$deadline" ] || return 1
    sleep 1 || return 1
  done
}

reload_vpn() {
  # Gluetun's custom OpenVPN provider reads OPENVPN_CUSTOM_CONFIG on every VPN
  # loop start. Stopping and starting that loop therefore applies the rendered
  # profile without granting the watcher access to the broader settings API.
  # The container network namespace remains stable throughout the reload.
  if ! gluetun_control_put /v1/vpn/status '{"status":"stopped"}'; then
    log ERROR "failed to confirm VPN stop through Gluetun control API; attempting recovery"
    gluetun_control_put /v1/vpn/status '{"status":"running"}' ||
      log ERROR "failed to recover VPN running state after stop error"
    return 1
  fi
  if ! gluetun_control_put /v1/vpn/status '{"status":"running"}'; then
    log ERROR "failed to start VPN through Gluetun control API; will retry"
    return 1
  fi
  if ! wait_gluetun_healthy; then
    log ERROR "Gluetun did not become healthy after in-place VPN reload timeout=${health_timeout}s; will retry"
    return 1
  fi
  if ! wait_vproxy_ready; then
    log ERROR "GOST SOCKS5 was not ready after in-place VPN reload timeout=${health_timeout}s; will retry"
    return 1
  fi

  return 0
}

watch_once() {
  if ! validate_config; then
    log ERROR "watch configuration validation failed"
    return 1
  fi
  if ! validate_control_api_key; then
    log ERROR "watcher control API key validation failed"
    return 1
  fi
  if ! ensure_heartbeat_writable; then
    log ERROR "watcher heartbeat directory is not writable directory=$(dirname "$heartbeat_file")"
    return 1
  fi

  if ! previous_ip=$(read_optional_state "$last_ip_file"); then
    log ERROR "failed to read previous DDNS state file=$last_ip_file"
    return 1
  fi
  if ! previous_hash=$(read_optional_state "$source_hash_file"); then
    log ERROR "failed to read source fingerprint file=$source_hash_file"
    return 1
  fi

  if ! selected_ip=$(resolve_and_select "$previous_ip"); then
    log WARN "DNS lookup failed hostname=$ddns_hostname; keeping current tunnel"
    finish_watch_once
    return $?
  fi

  if ! current_hash=$(source_hash); then
    log ERROR "failed to hash VPN source profile=$source_config"
    return 1
  fi
  [ -n "$current_hash" ] || {
    log ERROR "VPN source hash was empty profile=$source_config"
    return 1
  }
  if [ "$selected_ip" = "$previous_ip" ] &&
     [ "$current_hash" = "$previous_hash" ] &&
     [ -s "$rendered_config" ]; then
    finish_watch_once
    return $?
  fi

  reason=profile-change
  [ "$selected_ip" = "$previous_ip" ] || reason=address-change
  if ! render_config "$selected_ip"; then
    log ERROR "failed to render VPN profile output=$rendered_config"
    return 1
  fi
  if ! verified_hash=$(source_hash); then
    log ERROR "failed to verify VPN source profile after render profile=$source_config"
    return 1
  fi
  if [ "$verified_hash" != "$current_hash" ]; then
    log WARN "VPN source changed during render; refusing to restart profile=$source_config"
    return 1
  fi

  if reload_vpn; then
    if ! write_state "$selected_ip" "$last_ip_file"; then
      log ERROR "failed to commit DDNS state file=$last_ip_file"
      return 1
    fi
    if ! write_state "$current_hash" "$source_hash_file"; then
      log ERROR "failed to commit source fingerprint file=$source_hash_file"
      return 1
    fi
    log INFO "reloaded VPN in place vpn_type=$vpn_type reason=$reason hostname=$ddns_hostname old_ip=${previous_ip:-none} new_ip=$selected_ip"
    finish_watch_once
    return $?
  fi

  return 1
}

watch() {
  validate_config
  validate_control_api_key
  trap 'log INFO "watcher stopping"; exit 0' INT TERM
  log INFO "watching hostname=$ddns_hostname interval=${poll_seconds}s"

  while :; do
    if watch_once; then
      watch_status=0
    else
      watch_status=$?
      log ERROR "watch iteration failed; exiting for restart-policy recovery status=$watch_status"
      return "$watch_status"
    fi
    if [ "${WATCH_ONCE:-0}" = 1 ]; then
      return "$watch_status"
    fi
    sleep "$poll_seconds" || return 1
  done
}

healthcheck() {
  is_uint "$poll_seconds" || exit 1
  heartbeat=$(read_state "$heartbeat_file" || true)
  is_uint "$heartbeat" || exit 1
  now=$(date -u '+%s')
  maximum_age=$((poll_seconds * 3 + health_timeout + 30))
  age=$((now - heartbeat))
  [ "$age" -ge 0 ] && [ "$age" -le "$maximum_age" ]
}

usage() {
  cat <<'EOF'
Usage: ddns-openvpn.sh COMMAND

Commands:
  validate     Validate the selected OpenVPN profile and environment
  render IP    Render the Gluetun-compatible runtime profile with IP
  init         Resolve DDNS and render the initial runtime profile
  watch        Poll DDNS, render changes, and reload the VPN in place
  watch-once   Run one watcher iteration (primarily for diagnostics/tests)
  healthcheck  Check that the watcher loop is making progress
EOF
}

command=${1:-}
case $command in
  validate)
    validate_config
    validate_control_files
    validate_secret_files
    log INFO "configuration valid vpn_type=$vpn_type hostname=$ddns_hostname profile=$source_config"
    ;;
  render)
    validate_config
    [ "$#" -eq 2 ] || die "render requires one IPv4 address"
    is_ipv4 "$2" || die "invalid render IPv4 address: $2"
    render_config "$2"
    ;;
  init)
    initialize
    ;;
  watch)
    watch
    ;;
  watch-once)
    validate_config
    watch_once
    ;;
  healthcheck)
    healthcheck
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
