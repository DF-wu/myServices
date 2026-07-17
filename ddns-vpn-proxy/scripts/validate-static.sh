#!/bin/sh
set -eu

# 只做檔案、Compose model 與來源 profile 的靜態驗證。
# 本腳本不會 pull/build image，也不會 create/start/stop/restart/remove container。

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
compose_file=$repo_root/docker-compose.yml
common_env=$repo_root/.env.common.example
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

command -v docker >/dev/null 2>&1 || {
  printf 'ERROR: docker CLI not found\n' >&2
  exit 1
}
docker compose version >/dev/null

command -v jq >/dev/null 2>&1 || {
  printf 'ERROR: jq is required for rendered Compose contract checks\n' >&2
  exit 1
}

sh -n "$repo_root/scripts/ddns-openvpn.sh"

for token in \
  @GLUETUN_CONTAINER_NAME@ \
  @VPROXY_CONTAINER_NAME@ \
  @DEPENDENT_CONTAINER_NAME@
do
  grep -Fq "$token" "$repo_root/docker/socket-proxy-haproxy.cfg.tmpl" || {
    printf 'ERROR: socket policy placeholder missing: %s\n' "$token" >&2
    exit 1
  }
done
grep -Fq 'http-request deny' "$repo_root/docker/socket-proxy-haproxy.cfg.tmpl"

for region in jp romania uk
do
  region_env=$repo_root/env/$region.env.example
  model=$tmpdir/$region.json

  # 讀取範例 env 只用於比對 rendered model 與 host 上的來源 profile。
  # 每輪先覆寫已 export 的上一地區值，避免 shell environment 優先於
  # --env-file，導致 Romania/UK 意外沿用 JP 的 ports 與 container names。
  set -a
  # shellcheck disable=SC1090
  . "$common_env"
  # shellcheck disable=SC1090
  . "$region_env"
  set +a

  # Compose config/render 不會連線 Docker daemon，也不會更動現有服務。
  docker compose \
    --file "$compose_file" \
    --env-file "$common_env" \
    --env-file "$region_env" \
    config --format json >"$model"

  jq -e \
    --arg gluetun "$GLUETUN_CONTAINER_NAME" \
    --arg vproxy "$VPROXY_CONTAINER_NAME" \
    --arg http "$HTTP_PROXY_PORT" \
    --arg socks "$SOCKS5_PROXY_PORT" \
    --arg ss_tcp "$SHADOWSOCKS_TCP_PORT" \
    --arg ss_udp "$SHADOWSOCKS_UDP_PORT" '
      (.services | keys | sort) ==
        (["ddns-init", "ddns-watcher", "docker-socket-proxy", "gluetun", "vproxy"] | sort) and
      (all(.services[]; has("build") | not)) and
      (.services.gluetun.container_name == $gluetun) and
      (.services.vproxy.container_name == $vproxy) and
      (.services.vproxy.network_mode == "service:gluetun") and
      (.services."ddns-init".depends_on? == null) and
      (.services.gluetun.depends_on."ddns-init".condition == "service_completed_successfully") and
      (.networks."docker-api".internal == true) and
      (all(.services[]; (.security_opt // []) | index("no-new-privileges:true") != null)) and
      ([.services[] | .volumes // [] | .[] |
        select(.source == "/var/run/docker.sock")] | length == 1) and
      (any(.services.gluetun.ports[]; .target == 8888 and (.published | tostring) == $http and .protocol == "tcp")) and
      (any(.services.gluetun.ports[]; .target == 1080 and (.published | tostring) == $socks and .protocol == "tcp")) and
      (any(.services.gluetun.ports[]; .target == 8388 and (.published | tostring) == $ss_tcp and .protocol == "tcp")) and
      (any(.services.gluetun.ports[]; .target == 8388 and (.published | tostring) == $ss_udp and .protocol == "udp")) and
      (all(.services[]; (.image | test("(:latest|:edge|:main|:master)$")) | not))
    ' "$model" >/dev/null

  profile=$VPN_CONFIG_DIR/$VPN_CONFIG_FILE
  [ -r "$profile" ] && [ -s "$profile" ] || {
    printf 'ERROR: %s source profile missing or unreadable: %s\n' "$region" "$profile" >&2
    exit 1
  }

  remote_count=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "remote" { count++ }
    END { print count + 0 }
  ' "$profile")
  [ "$remote_count" -eq 1 ] || {
    printf 'ERROR: %s profile must have exactly one active remote\n' "$region" >&2
    exit 1
  }

  remote_host=$(awk '
    /^[[:space:]]*[#;]/ { next }
    $1 == "remote" { print $2; exit }
  ' "$profile")
  case $remote_host in
    ""|*[!A-Za-z0-9._-]*|[0-9]*.[0-9]*.[0-9]*.[0-9]*)
      printf 'ERROR: %s profile remote is not a DDNS hostname: %s\n' "$region" "$remote_host" >&2
      exit 1
      ;;
  esac

  printf 'ok - %s: compose model, compatibility contract and profile (%s)\n' \
    "$region" "$remote_host"
done

printf 'Static validation passed; no container lifecycle action was performed.\n'
