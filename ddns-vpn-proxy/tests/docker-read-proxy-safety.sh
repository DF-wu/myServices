#!/bin/sh
set -eu

# Exercise the Docker read-proxy gate with fake clients only. This test never
# contacts the Docker daemon or a live socket proxy.

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
subject=$repo_root/scripts/validate-docker-read-proxies.sh
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

shell=$(command -v sh) || fail 'POSIX shell is unavailable'
real_jq=$(command -v jq) || fail 'jq is unavailable for the test harness'
real_awk=$(command -v awk) || fail 'awk is unavailable for the test harness'
fake_bin=$workdir/bin
no_curl_bin=$workdir/no-curl-bin
docker_log=$workdir/docker.log
mkdir -p "$fake_bin" "$no_curl_bin"

cat >"$fake_bin/docker" <<'EOF'
#!/bin/sh
set -eu

[ "$#" -eq 4 ] && [ "$1" = inspect ] && [ "$2" = --type ] &&
  [ "$3" = container ] || exit 64
printf '%s\n' "$4" >>"$FAKE_DOCKER_LOG"

case ${FAKE_DOCKER_CASE:-safe} in
  safe)
    printf '%s\n' '[{"Id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","State":{"Running":true},"Config":{"ExposedPorts":{"2375/tcp":{}}},"NetworkSettings":{"Networks":{"proxy":{"IPAddress":"172.16.4.195"}},"Ports":{"2375/tcp":null}}}]'
    ;;
  missing)
    exit 1
    ;;
  no-ip)
    printf '%s\n' '[{"Id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","State":{"Running":true},"Config":{"ExposedPorts":{"2375/tcp":{}}},"NetworkSettings":{"Networks":{"proxy":{"IPAddress":""}},"Ports":{"2375/tcp":null}}}]'
    ;;
  multiple-ips)
    printf '%s\n' '[{"Id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","State":{"Running":true},"Config":{"ExposedPorts":{"2375/tcp":{}}},"NetworkSettings":{"Networks":{"one":{"IPAddress":"172.16.4.195"},"two":{"IPAddress":"172.16.5.2"}},"Ports":{"2375/tcp":null}}}]'
    ;;
  no-port)
    printf '%s\n' '[{"Id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","State":{"Running":true},"Config":{"ExposedPorts":{}},"NetworkSettings":{"Networks":{"proxy":{"IPAddress":"172.16.4.195"}},"Ports":{}}}]'
    ;;
  stopped)
    printf '%s\n' '[{"Id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","State":{"Running":false},"Config":{"ExposedPorts":{"2375/tcp":{}}},"NetworkSettings":{"Networks":{"proxy":{"IPAddress":"172.16.4.195"}},"Ports":{"2375/tcp":null}}}]'
    ;;
  published)
    printf '%s\n' '[{"Id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","State":{"Running":true},"Config":{"ExposedPorts":{"2375/tcp":{}}},"NetworkSettings":{"Networks":{"proxy":{"IPAddress":"172.16.4.195"}},"Ports":{"2375/tcp":[{"HostIp":"0.0.0.0","HostPort":"2375"}]}}}]'
    ;;
  *)
    exit 65
    ;;
esac
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/bin/sh
set -eu

[ "${1:-}" = --disable ] || exit 90
output=
previous=
url=
for argument
do
  if [ "$previous" = --output ]; then
    output=$argument
  fi
  previous=$argument
  url=$argument
done
[ "$output" = /dev/null ] || exit 91

case $url in
  *'/_ping') endpoint=ping ;;
  *'/json') endpoint=inspect ;;
  *'/top?ps_args=-o%20pid') endpoint=top ;;
  *'/archive?path=%2Fetc%2Fhostname') endpoint=archive ;;
  *'/logs?stdout=1&stderr=1&tail=0') endpoint=logs ;;
  *'/export') endpoint=export ;;
  *'/changes') endpoint=changes ;;
  *) exit 92 ;;
esac

if [ "${FAKE_CURL_FAIL:-}" = "$endpoint" ]; then
  exit 7
fi
if [ "${FAKE_CURL_FAIL:-}" = "status-zero-$endpoint" ]; then
  printf '000'
  exit 0
fi
if [ "$endpoint" = ping ] || [ "${FAKE_EXPOSE_ENDPOINT:-}" = "$endpoint" ]; then
  printf '200'
else
  printf '403'
fi
EOF

chmod 700 "$fake_bin/docker" "$fake_bin/curl"
ln -s "$real_jq" "$fake_bin/jq"
ln -s "$real_awk" "$fake_bin/awk"
ln -s "$fake_bin/docker" "$no_curl_bin/docker"
ln -s "$real_jq" "$no_curl_bin/jq"
ln -s "$real_awk" "$no_curl_bin/awk"

run_gate() {
  docker_case=$1
  exposed_endpoint=$2
  failed_endpoint=$3
  shift 3
  PATH="$fake_bin:$PATH" \
    FAKE_DOCKER_LOG="$docker_log" \
    FAKE_DOCKER_CASE="$docker_case" \
    FAKE_EXPOSE_ENDPOINT="$exposed_endpoint" \
    FAKE_CURL_FAIL="$failed_endpoint" \
    "$shell" "$subject" "$@"
}

expect_failure() {
  label=$1
  docker_case=$2
  exposed_endpoint=$3
  failed_endpoint=$4
  shift 4
  if run_gate "$docker_case" "$exposed_endpoint" "$failed_endpoint" "$@" \
    >"$workdir/stdout" 2>"$workdir/stderr"; then
    fail "$label"
  fi
  pass "$label"
}

: >"$docker_log"
if ! run_gate safe '' '' >"$workdir/stdout" 2>"$workdir/stderr"; then
  fail 'safe default proxies were rejected'
fi
expected_names=$(printf '%s\n' homepage-dockerproxy glance-dockerproxy)
actual_names=$(cat "$docker_log")
[ "$actual_names" = "$expected_names" ] ||
  fail 'the default proxy list was not inspected exactly'
pass 'safe default proxies pass'

: >"$docker_log"
if ! run_gate safe '' '' reviewed-proxy >"$workdir/stdout" 2>"$workdir/stderr"; then
  fail 'an explicit safe proxy was rejected'
fi
[ "$(cat "$docker_log")" = reviewed-proxy ] ||
  fail 'the explicit proxy list did not override defaults'
pass 'an explicit proxy-name override passes'

for endpoint in inspect top archive logs export changes
do
  expect_failure "$endpoint returning 2xx is rejected" safe "$endpoint" '' reviewed-proxy
done

expect_failure 'a missing proxy is rejected' missing '' '' reviewed-proxy
expect_failure 'a proxy without an IP is rejected' no-ip '' '' reviewed-proxy
expect_failure 'a proxy with multiple IPs is rejected' multiple-ips '' '' reviewed-proxy
expect_failure 'a proxy without 2375/tcp is rejected' no-port '' '' reviewed-proxy
expect_failure 'a stopped proxy is rejected' stopped '' '' reviewed-proxy
expect_failure 'a host-published 2375/tcp is rejected' published '' '' reviewed-proxy
expect_failure 'a failed health request is rejected' safe '' ping reviewed-proxy
expect_failure 'a failed sensitive endpoint request is rejected' safe '' archive reviewed-proxy
expect_failure 'an invalid HTTP 000 status is rejected' safe '' status-zero-archive reviewed-proxy

if PATH="$no_curl_bin" FAKE_DOCKER_LOG="$docker_log" \
  "$shell" "$subject" reviewed-proxy >"$workdir/stdout" 2>"$workdir/stderr"; then
  fail 'missing curl was accepted'
fi
pass 'missing curl is rejected'

printf 'Docker read-proxy safety tests passed.\n'
