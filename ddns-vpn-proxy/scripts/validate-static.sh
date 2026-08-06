#!/bin/sh
set -eu

# Read-only repository, installed asset and rendered Compose contract checks.
# This script never pulls/builds an image or changes a Docker object.

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
compose_file=$repo_root/docker-compose.yml
manifest=$repo_root/portainer/assets-2026-07-18.5.sha256
asset_root=${DDNS_VPN_INSTALLED_ASSET_DIR:-/home/df/.local/share/ddns-vpn-proxy/assets/2026-07-18.5}
private_root=${DDNS_VPN_INSTALLED_PRIVATE_DIR:-/home/df/.local/share/ddns-vpn-proxy/private/2026-07-18.5}
runtime_root=${DDNS_VPN_INSTALLED_RUNTIME_DIR:-/home/df/.local/share/ddns-vpn-proxy/runtime/2026-07-18.5}
profile_source=${SURFSHARK_PROFILE_DIR:-/mnt/appdata/gluetun/surfshark-ovpn}
regions='jp romania uk'
credential_names='openvpn-user openvpn-password httpproxy-user httpproxy-password shadowsocks-password'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for command_name in awk chmod cmp docker find grep install jq sed sha256sum sort stat wc
do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "required command not found: $command_name"
done
docker compose version >/dev/null 2>&1 || die 'docker compose is required'

required_files="
$compose_file
$repo_root/.dockerignore
$repo_root/docker/gluetun.Dockerfile
$repo_root/docker/gluetun/go.mod
$repo_root/docker/gluetun/go.sum
$repo_root/docker/gluetun/users.go
$repo_root/docker/gluetun/users_regression_test.go
$repo_root/docker/gost.Dockerfile
$repo_root/docker/gost/go.mod
$repo_root/docker/gost/go.sum
$repo_root/docker/gost-healthcheck.sh
$repo_root/security/gluetun-go-2026-5932.openvex.json
$repo_root/security/gost-go-2026-5932.openvex.json
$repo_root/scripts/ddns-openvpn.sh
$repo_root/scripts/audit-gluetun-binary.sh
$repo_root/scripts/audit-gost-binary.sh
$repo_root/scripts/install-portainer-assets.sh
$repo_root/scripts/validate-consumer-runtime.sh
$repo_root/scripts/validate-docker-read-proxies.sh
$repo_root/scripts/validate-portainer-env.sh
$repo_root/tests/consumer-safety.sh
$repo_root/tests/control-reload.sh
$repo_root/tests/docker-read-proxy-safety.sh
$repo_root/tests/openvpn-policy.sh
$repo_root/tests/portainer-assets.sh
$repo_root/tests/portainer-model-safety.sh
$manifest
"
printf '%s\n' "$required_files" |
while IFS= read -r required_file
do
  [ -n "$required_file" ] || continue
  [ -f "$required_file" ] && [ ! -L "$required_file" ] ||
    die "repository file is missing or symlinked: $required_file"
done

for shell_file in "$repo_root"/scripts/*.sh "$repo_root"/tests/*.sh
do
  sh -n "$shell_file" || die "shell syntax failed: $shell_file"
done

[ "$(wc -l <"$manifest")" -eq 4 ] ||
  die 'asset manifest must contain exactly four lines'
awk '
  NF != 2 || length($1) != 64 || $1 !~ /^[0-9a-f]+$/ { exit 1 }
' "$manifest" || die 'asset manifest contains an invalid entry'
manifest_paths=$(awk '{ print $2 }' "$manifest")
expected_manifest_paths=$(printf '%s\n' \
  ddns-openvpn.sh \
  profiles/jp-tok.prod.surfshark.com_udp.ovpn \
  profiles/ro-buc.prod.surfshark.com_udp.ovpn \
  profiles/uk-lon.prod.surfshark.com_udp.ovpn)
[ "$manifest_paths" = "$expected_manifest_paths" ] ||
  die 'asset manifest paths or ordering differ from the reviewed contract'

manifest_hash() {
  relative_path=$1
  awk -v path="$relative_path" '$2 == path { print $1; count++ } END { exit(count == 1 ? 0 : 1) }' \
    "$manifest"
}

verify_reviewed_hash() {
  source_file=$1
  relative_path=$2
  [ -f "$source_file" ] && [ ! -L "$source_file" ] ||
    die "reviewed source is missing or symlinked: $relative_path"
  expected_hash=$(manifest_hash "$relative_path") ||
    die "manifest hash is missing: $relative_path"
  actual_line=$(sha256sum "$source_file") ||
    die "failed to hash reviewed source: $relative_path"
  actual_hash=${actual_line%% *}
  [ "$actual_hash" = "$expected_hash" ] ||
    die "reviewed source hash differs from manifest: $relative_path"
}

verify_reviewed_hash "$repo_root/scripts/ddns-openvpn.sh" ddns-openvpn.sh
verify_reviewed_hash "$profile_source/jp-tok.prod.surfshark.com_udp.ovpn" \
  profiles/jp-tok.prod.surfshark.com_udp.ovpn
verify_reviewed_hash "$profile_source/ro-buc.prod.surfshark.com_udp.ovpn" \
  profiles/ro-buc.prod.surfshark.com_udp.ovpn
verify_reviewed_hash "$profile_source/uk-lon.prod.surfshark.com_udp.ovpn" \
  profiles/uk-lon.prod.surfshark.com_udp.ovpn

[ -d "$asset_root" ] && [ ! -L "$asset_root" ] ||
  die "installed asset version is missing or symlinked: $asset_root"
[ "$(stat -c '%a' "$asset_root")" = 500 ] ||
  die 'installed asset version must be mode 0500'
[ -d "$asset_root/profiles" ] && [ ! -L "$asset_root/profiles" ] ||
  die 'installed profile directory is missing or symlinked'
[ "$(stat -c '%a' "$asset_root/profiles")" = 500 ] ||
  die 'installed profile directory must be mode 0500'
actual_asset_entries=$(find "$asset_root" -mindepth 1 -maxdepth 2 -print | LC_ALL=C sort)
expected_asset_entries=$(printf '%s\n' \
  "$asset_root/ddns-openvpn.sh" \
  "$asset_root/profiles" \
  "$asset_root/profiles/jp-tok.prod.surfshark.com_udp.ovpn" \
  "$asset_root/profiles/ro-buc.prod.surfshark.com_udp.ovpn" \
  "$asset_root/profiles/uk-lon.prod.surfshark.com_udp.ovpn" | LC_ALL=C sort)
[ "$actual_asset_entries" = "$expected_asset_entries" ] ||
  die 'installed asset tree contains an unexpected entry'
for installed_file in \
  "$asset_root/ddns-openvpn.sh" \
  "$asset_root/profiles/jp-tok.prod.surfshark.com_udp.ovpn" \
  "$asset_root/profiles/ro-buc.prod.surfshark.com_udp.ovpn" \
  "$asset_root/profiles/uk-lon.prod.surfshark.com_udp.ovpn"
do
  [ -f "$installed_file" ] && [ ! -L "$installed_file" ] ||
    die "installed asset is missing or symlinked: $installed_file"
  [ "$(stat -c '%a' "$installed_file")" = 400 ] ||
    die "installed asset must be mode 0400: $installed_file"
done
(
  CDPATH='' cd -- "$asset_root"
  sha256sum -c "$manifest" >/dev/null
) || die 'installed asset hashes differ from the reviewed manifest'
cmp -s "$repo_root/scripts/ddns-openvpn.sh" "$asset_root/ddns-openvpn.sh" ||
  die 'installed helper differs from the repository helper'

[ -d "$private_root" ] && [ ! -L "$private_root" ] ||
  die "installed private version is missing or symlinked: $private_root"
[ "$(stat -c '%a' "$private_root")" = 500 ] ||
  die 'installed private version must be mode 0500'
actual_private_regions=$(find "$private_root" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
expected_private_regions=$(printf '%s\n' \
  "$private_root/jp" "$private_root/romania" "$private_root/uk" | LC_ALL=C sort)
[ "$actual_private_regions" = "$expected_private_regions" ] ||
  die 'installed private tree contains an unexpected region'

seen_keys=
for region in $regions
do
  region_root=$private_root/$region
  [ -d "$region_root" ] && [ ! -L "$region_root" ] ||
    die "private region is missing or symlinked: $region"
  [ "$(stat -c '%a' "$region_root")" = 500 ] ||
    die "private region must be mode 0500: $region"
  actual_region_entries=$(find "$region_root" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
  expected_region_entries=$(printf '%s\n' \
    "$region_root/control-api-key" \
    "$region_root/control-auth.toml" \
    "$region_root/control-default-role.json" \
    "$region_root/openvpn-user" \
    "$region_root/openvpn-password" \
    "$region_root/httpproxy-user" \
    "$region_root/httpproxy-password" \
    "$region_root/shadowsocks-password" | LC_ALL=C sort)
  [ "$actual_region_entries" = "$expected_region_entries" ] ||
    die "private region contains an unexpected entry: $region"

  for private_file in control-api-key control-auth.toml control-default-role.json $credential_names
  do
    [ -f "$region_root/$private_file" ] && [ ! -L "$region_root/$private_file" ] ||
      die "private file is missing or symlinked: $region/$private_file"
    [ "$(stat -c '%a' "$region_root/$private_file")" = 400 ] ||
      die "private file must be mode 0400: $region/$private_file"
  done

  control_key=$(sed -n '1p' "$region_root/control-api-key")
  [ "$(wc -l <"$region_root/control-api-key")" -eq 1 ] &&
    [ "$(wc -c <"$region_root/control-api-key")" -eq 65 ] ||
    die "control API key shape is invalid: $region"
  case $control_key in
    ''|*[!0-9a-f]*) die "control API key is not lowercase hexadecimal: $region" ;;
  esac
  [ "${#control_key}" -eq 64 ] || die "control API key length is invalid: $region"

  default_role=$(sed -n '1p' "$region_root/control-default-role.json")
  default_key=$(printf '%s\n' "$default_role" |
    sed -n 's/^{"name":"deny-default","auth":"apikey","apikey":"\([0-9a-f]*\)"}$/\1/p')
  [ "${#default_key}" -eq 64 ] || die "default role key length is invalid: $region"
  case $default_key in
    ''|*[!0-9a-f]*) die "default role key is not lowercase hexadecimal: $region" ;;
  esac
  [ "$default_key" != "$control_key" ] ||
    die "default role key equals watcher key: $region"

  for candidate_key in "$control_key" "$default_key"
  do
    for prior_key in $seen_keys
    do
      [ "$candidate_key" != "$prior_key" ] ||
        die "control/default keys are reused across regions: $region"
    done
    seen_keys="$seen_keys $candidate_key"
  done

  expected_auth=$( {
    printf '%s\n' '[[roles]]'
    printf '%s\n' 'name = "ddns-watcher"'
    printf '%s\n' 'auth = "apikey"'
    printf 'apikey = "%s"\n' "$control_key"
    printf '%s\n' 'routes = ["PUT /v1/vpn/status"]'
  } )
  actual_auth=$(sed -n '1,6p' "$region_root/control-auth.toml")
  [ "$(wc -l <"$region_root/control-auth.toml")" -eq 5 ] &&
    [ "$actual_auth" = "$expected_auth" ] ||
    die "control auth is not the exact status-only role: $region"
  [ "$default_role" = "{\"name\":\"deny-default\",\"auth\":\"apikey\",\"apikey\":\"$default_key\"}" ] ||
    die "default control role JSON is invalid: $region"

  for credential_name in $credential_names
  do
    LC_ALL=C awk '
      { if ($0 == "" || $0 ~ /[[:cntrl:]]/) exit 1; lines++ }
      END { exit(lines == 1 ? 0 : 1) }
    ' "$region_root/$credential_name" ||
      die "private credential is not one printable line: $region/$credential_name"
  done
done

[ -d "$runtime_root" ] && [ ! -L "$runtime_root" ] ||
  die "installed runtime version is missing or symlinked: $runtime_root"
[ "$(stat -c '%a' "$runtime_root")" = 500 ] ||
  die 'installed runtime version must be mode 0500'
actual_runtime_regions=$(find "$runtime_root" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
expected_runtime_regions=$(printf '%s\n' \
  "$runtime_root/jp" "$runtime_root/romania" "$runtime_root/uk" | LC_ALL=C sort)
[ "$actual_runtime_regions" = "$expected_runtime_regions" ] ||
  die 'installed runtime tree contains an unexpected region'
for region in $regions
do
  runtime_region=$runtime_root/$region
  [ -d "$runtime_region" ] && [ ! -L "$runtime_region" ] ||
    die "runtime region is missing or symlinked: $region"
  [ "$(stat -c '%a' "$runtime_region")" = 500 ] ||
    die "runtime region must be mode 0500: $region"
  [ "$(find "$runtime_region" -mindepth 1 -maxdepth 1 -print | wc -l)" -eq 1 ] ||
    die "runtime region contains an unexpected entry: $region"
  runtime_file=$runtime_region/resolv.conf
  [ -f "$runtime_file" ] && [ ! -L "$runtime_file" ] ||
    die "runtime resolver is missing or symlinked: $region"
  [ "$(stat -c '%a' "$runtime_file")" = 600 ] ||
    die "runtime resolver must be mode 0600: $region"
  [ "$(stat -c '%u:%g' "$runtime_file")" = 1000:1000 ] ||
    die "runtime resolver must be owned by UID/GID 1000: $region"
  [ "$(stat -c '%h' "$runtime_file")" = 1 ] ||
    die "runtime resolver must not be hard-linked: $region"
  [ "$(wc -l <"$runtime_file")" -eq 1 ] &&
    [ "$(sed -n '1p' "$runtime_file")" = 'nameserver 127.0.0.1' ] ||
    die "runtime resolver is not the fail-closed loopback value: $region"
done

if grep -R -n -E '2026-07-18\.[234]|/mnt/appdata/ddns-vpn-proxy' \
  "$repo_root" --exclude=validate-static.sh >/dev/null 2>&1; then
  die 'stale asset version or installation path remains in the repository'
fi
if grep -Fq '/v1/vpn/settings' "$repo_root/scripts/ddns-openvpn.sh"; then
  die 'production helper still requests broad VPN settings authority'
fi
grep -Fq 'routes = ["PUT /v1/vpn/status"]' "$repo_root/scripts/install-portainer-assets.sh" ||
  die 'installer does not generate the reviewed status-only route'
grep -Fq 'HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE' "$compose_file" ||
  die 'Compose does not install the deny-default control role'
grep -Fq 'VPN_SOURCE_SHA256' "$repo_root/scripts/ddns-openvpn.sh" ||
  die 'runtime helper does not verify the reviewed profile digest'
grep -Fq 'cipher must be exactly: cipher AES-256-CBC' "$repo_root/scripts/ddns-openvpn.sh" ||
  die 'runtime helper does not exact-pin the reviewed source profile cipher marker'
grep -Fq 'auth must be exactly: auth SHA512' "$repo_root/scripts/ddns-openvpn.sh" ||
  die 'runtime helper does not exact-pin OpenVPN packet authentication'
# shellcheck disable=SC2016 # Compose command is matched as literal text.
grep -Fq 'test "$${actual_auth}" = "$${expected_auth}"' "$compose_file" ||
  die 'Gluetun point-of-use wrapper does not exact-check control auth'
grep -Fq 'OPENVPN_FLAGS: --group nonrootuser --cipher AES-256-GCM --data-ciphers AES-256-GCM' \
  "$compose_file" || die 'OpenVPN runtime does not exact-pin UID/GID drop and AES-256-GCM only'
grep -Fq 'HEALTH_SMALL_CHECK_TYPE: dns' "$compose_file" ||
  die 'Gluetun healthcheck would require an ungranted raw-socket capability'
grep -Fq "nameserver 127.0.0.1" "$compose_file" ||
  die 'Gluetun point-of-use wrapper does not fail closed on resolver state'

grep -Fq 'image: alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b' \
  "$compose_file" || die 'helper runtime image is not exact-pinned'
[ "$(grep -Ec '^    pull_policy: build$' "$compose_file")" -eq 2 ] ||
  die 'both repo-built images must use pull_policy build'
[ "$(grep -Ec '^    build:$' "$compose_file")" -eq 2 ] ||
  die 'Gluetun and GOST must be built from the repository'
grep -Fq 'dockerfile: docker/gluetun.Dockerfile' "$compose_file" ||
  die 'Compose does not select the reviewed Gluetun Dockerfile'
grep -Fq 'dockerfile: docker/gost.Dockerfile' "$compose_file" ||
  die 'Compose does not select the reviewed GOST Dockerfile'
if grep -Eq 'ghcr\.io/df-wu/ddns-vpn-|@sha256:0{64}' "$compose_file"; then
  die 'obsolete unpublished image reference remains in Compose'
fi
[ "$(grep -Ec '^FROM ' "$repo_root/docker/gost.Dockerfile")" -eq 2 ] ||
  die 'GOST wrapper must contain exactly two image stages'
# The Dockerfile automatic argument is intentionally checked as literal text.
# shellcheck disable=SC2016
grep -Fxq 'FROM --platform=$BUILDPLATFORM golang:1.26.5-alpine3.24@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS builder' \
  "$repo_root/docker/gost.Dockerfile" || die 'GOST builder is not exact-pinned'
grep -Fxq 'FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b' \
  "$repo_root/docker/gost.Dockerfile" || die 'GOST runtime base is not exact-pinned'
grep -Fq 'https://codeload.github.com/go-gost/gost/tar.gz/5a01aa4fd2085156f1f6138774a9a399dbb92e1a' \
  "$repo_root/docker/gost.Dockerfile" || die 'GOST source revision is not exact-pinned'
grep -Fq 'ADD --checksum=sha256:f6f52fbe825c00ff7e102f956d0c055527f81606387b33ccfb476acf8e8a88ec' \
  "$repo_root/docker/gost.Dockerfile" || die 'GOST source archive is not checksum-pinned'
grep -Fxq 'COPY docker/gost/go.mod docker/gost/go.sum /src/' \
  "$repo_root/docker/gost.Dockerfile" || die 'GOST reviewed module files are not copied into the source stage'
grep -Fq 'go build -mod=readonly -trimpath -buildvcs=false' \
  "$repo_root/docker/gost.Dockerfile" || die 'GOST build is not readonly and reproducible'
grep -Fq 'go list -mod=readonly -deps -test ./...' \
  "$repo_root/docker/gost.Dockerfile" || die 'GOST test dependency graph is not audited'
grep -Fq "! grep -Eq '^golang\\.org/x/crypto/openpgp(/|$)' /tmp/gost-production-packages" \
  "$repo_root/docker/gost.Dockerfile" || die 'GOST production graph lacks the openpgp exclusion gate'
grep -Fq 'golang.org/x/text v0.39.0' "$repo_root/docker/gost/go.mod" ||
  die 'GOST x/text security update is missing'
grep -Fq 'golang.org/x/net v0.56.0' "$repo_root/docker/gost/go.mod" ||
  die 'GOST x/net security update is missing'
grep -Fq 'golang.org/x/crypto v0.53.0' "$repo_root/docker/gost/go.mod" ||
  die 'GOST x/crypto version is not reviewed'
if grep -Eq '^(replace|exclude|retract|tool|godebug)[[:space:]]' "$repo_root/docker/gost/go.mod"; then
  die 'GOST module file contains an unreviewed dependency override'
fi
grep -Fxq 'USER 65532:65532' "$repo_root/docker/gost.Dockerfile" ||
  die 'GOST image does not run as the reviewed unprivileged UID'
grep -Fxq 'ENTRYPOINT ["/usr/local/bin/gost"]' "$repo_root/docker/gost.Dockerfile" ||
  die 'GOST entrypoint differs from the reviewed binary'
grep -Fq '05000500' "$repo_root/docker/gost-healthcheck.sh" ||
  die 'GOST healthcheck does not exact-check greeting and CONNECT success'
grep -Fq 'service.dialTimeout=10s' "$compose_file" ||
  die 'GOST outbound connection deadline is not exact-pinned'
grep -Fq 'vulnerable_code_not_present' \
  "$repo_root/security/gost-go-2026-5932.openvex.json" ||
  die 'GOST VEX does not use the reviewed not-present justification'
jq -e '
  .["@context"] == "https://openvex.dev/ns/v0.2.0" and
  (.statements | length) == 1 and
  .statements[0].vulnerability.name == "GO-2026-5932" and
  .statements[0].status == "not_affected" and
  (.statements[0].products | length) == 2 and
  all(.statements[0].products[];
    .["@id"] == "pkg:golang/github.com/go-gost/gost" and
    .subcomponents == [{"@id": "pkg:golang/golang.org/x/crypto@v0.53.0"}]
  )
' "$repo_root/security/gost-go-2026-5932.openvex.json" >/dev/null ||
  die 'GOST OpenVEX structure or scope is invalid'
grep -Fq 'golang:1.25.12-alpine3.23@sha256:cc985ef6f9c3bf9ece7488129c9abe0a150388ccdfa428d886fc709dca0b230a' \
  "$repo_root/docker/gluetun.Dockerfile" || die 'Gluetun builder is not exact-pinned'
grep -Fq 'qmcgaw/gluetun:latest@sha256:b0ee2135e6ba52ad3f102aae9663707cd1c9531485117067a380d3b2b6dd991d' \
  "$repo_root/docker/gluetun.Dockerfile" || die 'Gluetun runtime base is not exact-pinned'
grep -Fq 'ADD --checksum=sha256:3c2915cfaa220b7384c00bbcc7d5a60819eacbf4bd2a8a5bfa3efa4965e75918' \
  "$repo_root/docker/gluetun.Dockerfile" || die 'Gluetun source archive is not checksum-pinned'
grep -Fq 'golang.org/x/crypto v0.53.0' "$repo_root/docker/gluetun/go.mod" ||
  die 'Gluetun x/crypto security update is missing'
grep -Fq "! grep -Eq '^golang[.]org/x/crypto/openpgp(/|$)' /tmp/gluetun-deps" \
  "$repo_root/docker/gluetun.Dockerfile" ||
  die 'Gluetun production graph lacks the openpgp exclusion gate'
if grep -Eq '^(replace|exclude|retract|tool|godebug)[[:space:]]' \
  "$repo_root/docker/gluetun/go.mod"; then
  die 'Gluetun module file contains an unreviewed dependency override'
fi
grep -Fq 'return u.Username, nil' "$repo_root/docker/gluetun/users.go" ||
  die 'Gluetun matching-user runtime patch is missing'
grep -Fq 'TestCreateUserReturnsExistingMatchingUsername' \
  "$repo_root/docker/gluetun/users_regression_test.go" ||
  die 'Gluetun matching-user regression test is missing'
jq -e '
  .["@context"] == "https://openvex.dev/ns/v0.2.0" and
  (.statements | length) == 1 and
  .statements[0].vulnerability.name == "GO-2026-5932" and
  .statements[0].status == "not_affected" and
  .statements[0].justification == "vulnerable_code_not_present" and
  (.statements[0].products | length) == 2 and
  all(.statements[0].products[];
    .["@id"] == "pkg:golang/github.com/qdm12/gluetun" and
    .subcomponents == [{"@id": "pkg:golang/golang.org/x/crypto@v0.53.0"}]
  )
' "$repo_root/security/gluetun-go-2026-5932.openvex.json" >/dev/null ||
  die 'Gluetun OpenVEX structure or scope is invalid'

assert_file_sha256() {
  reviewed_file=$1
  reviewed_sha=$2
  actual_line=$(sha256sum "$reviewed_file") || return 1
  [ "${actual_line%% *}" = "$reviewed_sha" ]
}
assert_file_sha256 "$repo_root/docker/gost.Dockerfile" \
  312b266aa2b324547478cf4c87cc29bda3ce421ccb1dd4b90703e5a9be09baa2 ||
  die 'GOST wrapper differs from the complete reviewed recipe'
assert_file_sha256 "$repo_root/docker/gost/go.mod" \
  b27e0a2c8ab2e5e0d0d263da1daabf3c2230bc51e16970925a96bd4712e307eb ||
  die 'GOST go.mod differs from the reviewed dependency graph'
assert_file_sha256 "$repo_root/docker/gost/go.sum" \
  c6bee4e80c96f4cb1cdcf04d70711f826bcee5bc19982472fd1c239525e644cb ||
  die 'GOST go.sum differs from the reviewed dependency checksums'
assert_file_sha256 "$repo_root/security/gost-go-2026-5932.openvex.json" \
  5cbc794b1b9dffe7e3c8bb0de9a48e42e3b03bac2ac43148f9b000bcdf8313c1 ||
  die 'GOST OpenVEX differs from the reviewed evidence statement'
assert_file_sha256 "$repo_root/scripts/audit-gost-binary.sh" \
  f60413482a5ccfc8dcf3371e9cab9377110e7a414a628454b658bcf1c28f3b5d ||
  die 'GOST binary audit differs from the reviewed fail-closed gate'
assert_file_sha256 "$repo_root/docker/gost-healthcheck.sh" \
  625850817c2518eee145af3855abc001af8419f79de6ebecc1effbc628595607 ||
  die 'GOST healthcheck differs from the complete reviewed protocol probe'
assert_file_sha256 "$repo_root/docker/gluetun/users.go" \
  76bcf7e748bfd230647bb1c447ee9f940a8bb47f7585e2d76a276f4d19088b53 ||
  die 'Gluetun matching-user patch differs from the reviewed source'
assert_file_sha256 "$repo_root/docker/gluetun/users_regression_test.go" \
  0ffcb16838b68608bbde3ba33faaee6784e8a8ce90ab24391c5ba3112b49f62e ||
  die 'Gluetun matching-user regression test differs from the reviewed source'
assert_file_sha256 "$repo_root/docker/gluetun/go.mod" \
  f241ee1705ef1e67c85ede7293b3ddefcef507339d9c35fa77bd590fe1d0ec9d ||
  die 'Gluetun go.mod differs from the reviewed dependency graph'
assert_file_sha256 "$repo_root/docker/gluetun/go.sum" \
  b977d62c1dac433506e6dd61d37c1e9214c8610d7602314684fa7afb3a2cd383 ||
  die 'Gluetun go.sum differs from the reviewed dependency checksums'
assert_file_sha256 "$repo_root/docker/gluetun.Dockerfile" \
  5c5731c9eea1b260fd808a2a5cf29ed4f32e44af0e8d73c6f71d45a0c157ada2 ||
  die 'Gluetun image differs from the complete reviewed build recipe'
assert_file_sha256 "$repo_root/security/gluetun-go-2026-5932.openvex.json" \
  46a834e054495cfcaa800f16db9ad9ffb16aab2f8a82277495650a927f566103 ||
  die 'Gluetun OpenVEX differs from the reviewed evidence statement'
assert_file_sha256 "$repo_root/scripts/audit-gluetun-binary.sh" \
  fb12d71e2babe901b1f46267ee5206bec22064195e56cb3bfc9eedab3ccb324b ||
  die 'Gluetun binary audit differs from the reviewed fail-closed gate'

if grep -R -i -n 'microsocks\|docker/socks5\.Dockerfile' "$repo_root" \
  --exclude=validate-static.sh >/dev/null 2>&1; then
  die 'rejected MicroSocks implementation or build recipe remains in the repository'
fi

expected_dockerignore=$(printf '%s\n' \
  '**' \
  '!docker/gost.Dockerfile' \
  '!docker/gost-healthcheck.sh' \
  '!docker/gost/' \
  '!docker/gost/go.mod' \
  '!docker/gost/go.sum' \
  '!docker/gluetun.Dockerfile' \
  '!docker/gluetun/' \
  '!docker/gluetun/go.mod' \
  '!docker/gluetun/go.sum' \
  '!docker/gluetun/users.go' \
  '!docker/gluetun/users_regression_test.go' \
  '!scripts/ddns-openvpn.sh')
actual_dockerignore=$(sed -n '1,20p' "$repo_root/.dockerignore")
[ "$actual_dockerignore" = "$expected_dockerignore" ] ||
  die '.dockerignore does not restrict the three image build contexts'

for region in $regions
do
  case $region in
    jp) project=ddns-vpn-proxy-jp ;;
    romania) project=ddns-vpn-proxy-romania ;;
    uk) project=ddns-vpn-proxy-uk ;;
  esac
  env_copy=$tmpdir/$region.env
  install -m 0600 -- "$repo_root/portainer/$region.env.example" "$env_copy"
  sh "$repo_root/scripts/validate-portainer-env.sh" "$region" "$project" "$env_copy" >/dev/null
  printf 'ok - %s installed assets, private files and Portainer model\n' "$region"
done

sh "$repo_root/tests/control-reload.sh"
sh "$repo_root/tests/openvpn-policy.sh"
sh "$repo_root/tests/consumer-safety.sh"
sh "$repo_root/tests/docker-read-proxy-safety.sh"
sh "$repo_root/tests/portainer-assets.sh"
sh "$repo_root/tests/portainer-model-safety.sh"

printf 'Static validation passed; no Docker lifecycle action was performed.\n'
