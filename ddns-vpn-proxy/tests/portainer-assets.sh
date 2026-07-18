#!/bin/sh
set -eu

# Verify the host-side Portainer asset installer without touching its default
# publication roots.  The temporary workspace lives below /home/df so the
# installer's strict ancestor-permission checks remain exercised.

umask 077

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
installer=$repo_root/scripts/install-portainer-assets.sh
manifest=$repo_root/portainer/assets-2026-07-18.5.sha256
profile_source=${SURFSHARK_PROFILE_DIR:-/mnt/appdata/gluetun/surfshark-ovpn}
workdir=$(mktemp -d /home/df/.ddns-vpn-assets-test.XXXXXX)
fixture_source=$workdir/source
credential_source=$workdir/credentials

jp_name=jp-tok.prod.surfshark.com_udp.ovpn
ro_name=ro-buc.prod.surfshark.com_udp.ovpn
uk_name=uk-lon.prod.surfshark.com_udp.ovpn
region_names='jp romania uk'
credential_names='openvpn-user openvpn-password httpproxy-user httpproxy-password shadowsocks-password'

cleanup() {
  chmod -R u+rwX "$workdir" 2>/dev/null || :
  rm -rf "$workdir"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

mkdir -m 0700 "$fixture_source"
for profile_name in "$jp_name" "$ro_name" "$uk_name"
do
  [ -f "$profile_source/$profile_name" ] && [ ! -L "$profile_source/$profile_name" ] ||
    fail "profile fixture is missing: $profile_name"
  cp -- "$profile_source/$profile_name" "$fixture_source/$profile_name"
done

mkdir -m 0700 "$credential_source"
for region_name in $region_names
do
  mkdir -m 0700 "$credential_source/$region_name"
  for credential_name in $credential_names
  do
    printf '%s\n' "${region_name}-${credential_name}-fixture-value" \
      >"$credential_source/$region_name/$credential_name"
    case $credential_name in
      *password) chmod 0600 "$credential_source/$region_name/$credential_name" ;;
      *) chmod 0400 "$credential_source/$region_name/$credential_name" ;;
    esac
  done
done

run_installer_inputs() {
  target_root=$1
  script_path=$2
  profile_input=$3
  credential_input=$4
  DDNS_VPN_ASSET_ROOT="$target_root/assets" \
  DDNS_VPN_PRIVATE_ROOT="$target_root/private" \
  DDNS_VPN_RUNTIME_ROOT="$target_root/runtime" \
  SURFSHARK_PROFILE_DIR="$profile_input" \
  DDNS_VPN_CREDENTIAL_SOURCE_DIR="$credential_input" \
  sh "$script_path"
}

run_installer_at() {
  run_installer_inputs "$1" "$2" "$fixture_source" "$credential_source"
}

assert_asset_tree() {
  target_root=$1
  asset_tree=$target_root/assets/2026-07-18.5
  [ -d "$asset_tree" ] || fail 'published asset version is missing'
  [ ! -L "$asset_tree" ] || fail 'published asset version is a symlink'
  [ "$(stat -c '%a' "$asset_tree")" = 500 ] || fail 'asset version is not mode 0500'
  [ "$(stat -c '%a' "$asset_tree/profiles")" = 500 ] || fail 'profile directory is not mode 0500'
  for relative_path in \
    ddns-openvpn.sh \
    profiles/$jp_name \
    profiles/$ro_name \
    profiles/$uk_name
  do
    [ -f "$asset_tree/$relative_path" ] && [ ! -L "$asset_tree/$relative_path" ] ||
      fail "published asset is missing or symlinked: $relative_path"
    [ "$(stat -c '%a' "$asset_tree/$relative_path")" = 400 ] ||
      fail "published asset is not mode 0400: $relative_path"
  done
  [ "$(find "$asset_tree" -mindepth 1 -maxdepth 2 -print | wc -l)" -eq 5 ] ||
    fail 'published asset tree contains an unexpected entry'
}

assert_private_tree() {
  target_root=$1
  private_tree=$target_root/private/2026-07-18.5
  [ -d "$private_tree" ] || fail 'published private version is missing'
  [ ! -L "$private_tree" ] || fail 'published private version is a symlink'
  [ "$(stat -c '%a' "$private_tree")" = 500 ] || fail 'private version is not mode 0500'
  [ "$(find "$private_tree" -mindepth 1 -maxdepth 1 -print | wc -l)" -eq 3 ] ||
    fail 'private version contains an unexpected region entry'
  seen_test_keys=
  for region_name in $region_names
  do
    region_tree=$private_tree/$region_name
    [ -d "$region_tree" ] && [ ! -L "$region_tree" ] ||
      fail "private region is missing or symlinked: $region_name"
    [ "$(stat -c '%a' "$region_tree")" = 500 ] ||
      fail "private region is not mode 0500: $region_name"
    [ "$(find "$region_tree" -mindepth 1 -maxdepth 1 -print | wc -l)" -eq 8 ] ||
      fail "private region contains an unexpected entry: $region_name"

    control_key=$(sed -n '1p' "$region_tree/control-api-key")
    [ "$(wc -l <"$region_tree/control-api-key")" -eq 1 ] ||
      fail "control key has multiple lines: $region_name"
    [ "$(wc -c <"$region_tree/control-api-key")" -eq 65 ] ||
      fail "control key has an unexpected length: $region_name"
    case $control_key in
      ''|*[!0-9a-f]*) fail "control key is not lowercase hexadecimal: $region_name" ;;
    esac
    [ "${#control_key}" -eq 64 ] || fail "control key is not 64 characters: $region_name"
    for prior_key in $seen_test_keys
    do
      [ "$prior_key" != "$control_key" ] || fail "control/default keys are not unique: $region_name"
    done
    seen_test_keys="$seen_test_keys $control_key"

    expected_auth=$( {
      printf '%s\n' '[[roles]]'
      printf '%s\n' 'name = "ddns-watcher"'
      printf '%s\n' 'auth = "apikey"'
      printf 'apikey = "%s"\n' "$control_key"
      printf '%s\n' 'routes = ["PUT /v1/vpn/status"]'
    } )
    actual_auth=$(sed -n '1,20p' "$region_tree/control-auth.toml")
    [ "$actual_auth" = "$expected_auth" ] ||
      fail "control-auth.toml does not match the control key: $region_name"
    if printf '%s' "$actual_auth" | grep -Fq 'PUT /v1/vpn/settings'; then
      fail "control-auth.toml grants the settings route: $region_name"
    fi

    default_line=$(sed -n '1p' "$region_tree/control-default-role.json")
    default_key=$(printf '%s\n' "$default_line" |
      sed -n 's/^{"name":"deny-default","auth":"apikey","apikey":"\([0-9a-f]*\)"}$/\1/p')
    case $default_key in
      ''|*[!0-9a-f]*) fail "default role key is invalid: $region_name" ;;
    esac
    [ "${#default_key}" -eq 64 ] || fail "default role key is not 64 characters: $region_name"
    for prior_key in $seen_test_keys
    do
      [ "$prior_key" != "$default_key" ] || fail "control/default keys are not unique: $region_name"
    done
    seen_test_keys="$seen_test_keys $default_key"
    expected_default=$(printf '{"name":"deny-default","auth":"apikey","apikey":"%s"}\n' "$default_key")
    [ "$default_line" = "$expected_default" ] ||
      fail "default role JSON does not match its key: $region_name"
    [ "$(wc -l <"$region_tree/control-default-role.json")" -eq 1 ] ||
      fail "default role JSON has multiple lines: $region_name"
    [ -z "$(sed -n '2p' "$region_tree/control-default-role.json")" ] ||
      fail "default role JSON has trailing data: $region_name"

    for private_file in control-api-key control-auth.toml control-default-role.json
    do
      [ -f "$region_tree/$private_file" ] && [ ! -L "$region_tree/$private_file" ] ||
        fail "private file is missing or symlinked: $region_name/$private_file"
      [ "$(stat -c '%a' "$region_tree/$private_file")" = 400 ] ||
        fail "private file is not mode 0400: $region_name/$private_file"
    done
    for credential_name in $credential_names
    do
      [ -f "$region_tree/$credential_name" ] && [ ! -L "$region_tree/$credential_name" ] ||
        fail "private credential is missing or symlinked: $region_name/$credential_name"
      [ "$(stat -c '%a' "$region_tree/$credential_name")" = 400 ] ||
        fail "private credential is not mode 0400: $region_name/$credential_name"
      cmp -s "$credential_source/$region_name/$credential_name" \
        "$region_tree/$credential_name" ||
        fail "private credential differs from source: $region_name/$credential_name"
    done
  done
}

assert_runtime_tree() {
  target_root=$1
  runtime_tree=$target_root/runtime/2026-07-18.5
  [ -d "$runtime_tree" ] && [ ! -L "$runtime_tree" ] ||
    fail 'published runtime version is missing or symlinked'
  [ "$(stat -c '%a' "$runtime_tree")" = 500 ] || fail 'runtime version is not mode 0500'
  [ "$(find "$runtime_tree" -mindepth 1 -maxdepth 2 -print | wc -l)" -eq 6 ] ||
    fail 'runtime version contains an unexpected entry'
  for region_name in $region_names
  do
    region_tree=$runtime_tree/$region_name
    [ -d "$region_tree" ] && [ ! -L "$region_tree" ] ||
      fail "runtime region is missing or symlinked: $region_name"
    [ "$(stat -c '%a' "$region_tree")" = 500 ] ||
      fail "runtime region is not mode 0500: $region_name"
    resolver_file=$region_tree/resolv.conf
    [ -f "$resolver_file" ] && [ ! -L "$resolver_file" ] ||
      fail "runtime resolver is missing or symlinked: $region_name"
    [ "$(stat -c '%a' "$resolver_file")" = 600 ] ||
      fail "runtime resolver is not mode 0600: $region_name"
    [ "$(stat -c '%u:%g' "$resolver_file")" = 1000:1000 ] ||
      fail "runtime resolver has the wrong owner: $region_name"
    [ "$(stat -c '%h' "$resolver_file")" = 1 ] ||
      fail "runtime resolver is hard-linked: $region_name"
    [ "$(cat "$resolver_file")" = 'nameserver 127.0.0.1' ] ||
      fail "runtime resolver is not fail-closed: $region_name"
  done
}

# Initial publication and a second run must preserve the generated credential.
base=$workdir/base
mkdir -m 0700 "$base"
run_installer_at "$base" "$installer" >"$workdir/install.log" 2>&1 ||
  fail 'installer rejected reviewed source assets'
assert_asset_tree "$base"
assert_private_tree "$base"
assert_runtime_tree "$base"
private_before=$workdir/private-before.sha256
runtime_before=$workdir/runtime-before.sha256
(
  cd "$base/private/2026-07-18.5"
  sha256sum jp/* romania/* uk/*
) >"$private_before"
(
  cd "$base/runtime/2026-07-18.5"
  sha256sum jp/resolv.conf romania/resolv.conf uk/resolv.conf
) >"$runtime_before"
for region_name in $region_names
do
  for private_file in control-api-key control-default-role.json
  do
    secret_value=$(sed -n '1p' "$base/private/2026-07-18.5/$region_name/$private_file")
    if [ "$private_file" = control-default-role.json ]; then
      secret_value=$(printf '%s\n' "$secret_value" |
        sed -n 's/^.*"apikey":"\([0-9a-f]*\)"}$/\1/p')
    fi
    if grep -Fq "$secret_value" "$workdir/install.log"; then
      fail "installer leaked a generated key: $region_name/$private_file"
    fi
  done
done
if grep -Fq 'fixture-value' "$workdir/install.log"; then
  fail 'installer leaked a credential value to its output'
fi
run_installer_at "$base" "$installer" >/dev/null || fail 'matching version is not idempotent'
(
  cd "$base/private/2026-07-18.5"
  sha256sum jp/* romania/* uk/*
) >"$workdir/private-after.sha256"
(
  cd "$base/runtime/2026-07-18.5"
  sha256sum jp/resolv.conf romania/resolv.conf uk/resolv.conf
) >"$workdir/runtime-after.sha256"
cmp -s "$private_before" "$workdir/private-after.sha256" ||
  fail 'idempotent install changed private credentials'
cmp -s "$runtime_before" "$workdir/runtime-after.sha256" ||
  fail 'idempotent install changed runtime resolver files'
printf 'ok - installer publishes assets, private credentials and resolver files\n'

# Existing immutable trees are never silently repaired or replaced.
asset_tamper=$workdir/asset-tamper
mkdir -m 0700 "$asset_tamper"
run_installer_at "$asset_tamper" "$installer" >/dev/null || fail 'asset tamper fixture setup failed'
chmod 700 "$asset_tamper/assets/2026-07-18.5"
chmod 600 "$asset_tamper/assets/2026-07-18.5/ddns-openvpn.sh"
printf '%s\n' '# tamper' >>"$asset_tamper/assets/2026-07-18.5/ddns-openvpn.sh"
chmod 500 "$asset_tamper/assets/2026-07-18.5"
if run_installer_at "$asset_tamper" "$installer" >/dev/null 2>&1; then
  fail 'installer accepted a tampered existing asset tree'
fi
printf 'ok - installer refuses to overwrite tampered assets\n'

private_tamper=$workdir/private-tamper
mkdir -m 0700 "$private_tamper"
run_installer_at "$private_tamper" "$installer" >/dev/null || fail 'private tamper fixture setup failed'
chmod 700 "$private_tamper/private/2026-07-18.5"
chmod 700 "$private_tamper/private/2026-07-18.5/jp"
chmod 600 "$private_tamper/private/2026-07-18.5/jp/control-api-key"
printf '%s\n' 'not-a-valid-key' >"$private_tamper/private/2026-07-18.5/jp/control-api-key"
chmod 400 "$private_tamper/private/2026-07-18.5/jp/control-api-key"
chmod 500 "$private_tamper/private/2026-07-18.5/jp"
chmod 500 "$private_tamper/private/2026-07-18.5"
if run_installer_at "$private_tamper" "$installer" >/dev/null 2>&1; then
  fail 'installer accepted a tampered private key'
fi
printf 'ok - installer refuses a malformed private credential\n'

runtime_tamper=$workdir/runtime-tamper
mkdir -m 0700 "$runtime_tamper"
run_installer_at "$runtime_tamper" "$installer" >/dev/null || fail 'runtime tamper fixture setup failed'
chmod 700 "$runtime_tamper/runtime/2026-07-18.5"
chmod 700 "$runtime_tamper/runtime/2026-07-18.5/jp"
printf '%s\n' 'nameserver 1.1.1.1' >"$runtime_tamper/runtime/2026-07-18.5/jp/resolv.conf"
chmod 600 "$runtime_tamper/runtime/2026-07-18.5/jp/resolv.conf"
chmod 500 "$runtime_tamper/runtime/2026-07-18.5/jp"
chmod 500 "$runtime_tamper/runtime/2026-07-18.5"
if run_installer_at "$runtime_tamper" "$installer" >/dev/null 2>&1; then
  fail 'installer accepted a non-loopback runtime resolver'
fi
printf 'ok - installer refuses a tampered runtime resolver\n'

auth_tamper=$workdir/auth-tamper
mkdir -m 0700 "$auth_tamper"
run_installer_at "$auth_tamper" "$installer" >/dev/null || fail 'auth tamper fixture setup failed'
auth_key=$(sed -n '1p' "$auth_tamper/private/2026-07-18.5/jp/control-api-key")
case $auth_key in
  0*) mismatched_auth_key=1${auth_key#?} ;;
  *) mismatched_auth_key=0${auth_key#?} ;;
esac
chmod 700 "$auth_tamper/private/2026-07-18.5"
chmod 700 "$auth_tamper/private/2026-07-18.5/jp"
chmod 600 "$auth_tamper/private/2026-07-18.5/jp/control-auth.toml"
{
  printf '%s\n' '[[roles]]'
  printf '%s\n' 'name = "ddns-watcher"'
  printf '%s\n' 'auth = "apikey"'
  printf 'apikey = "%s"\n' "$mismatched_auth_key"
  printf '%s\n' 'routes = ["PUT /v1/vpn/status"]'
} >"$auth_tamper/private/2026-07-18.5/jp/control-auth.toml"
chmod 400 "$auth_tamper/private/2026-07-18.5/jp/control-auth.toml"
chmod 500 "$auth_tamper/private/2026-07-18.5/jp"
chmod 500 "$auth_tamper/private/2026-07-18.5"
if run_installer_at "$auth_tamper" "$installer" >/dev/null 2>&1; then
  fail 'installer accepted a control-auth key mismatch'
fi
printf 'ok - installer refuses a control-auth key mismatch\n'

default_tamper=$workdir/default-tamper
mkdir -m 0700 "$default_tamper"
run_installer_at "$default_tamper" "$installer" >/dev/null || fail 'default-role fixture setup failed'
duplicate_key=$(sed -n '1p' "$default_tamper/private/2026-07-18.5/jp/control-api-key")
chmod 700 "$default_tamper/private/2026-07-18.5"
chmod 700 "$default_tamper/private/2026-07-18.5/jp"
chmod 600 "$default_tamper/private/2026-07-18.5/jp/control-default-role.json"
printf '{"name":"deny-default","auth":"apikey","apikey":"%s"}\n' "$duplicate_key" \
  >"$default_tamper/private/2026-07-18.5/jp/control-default-role.json"
chmod 400 "$default_tamper/private/2026-07-18.5/jp/control-default-role.json"
chmod 500 "$default_tamper/private/2026-07-18.5/jp"
chmod 500 "$default_tamper/private/2026-07-18.5"
if run_installer_at "$default_tamper" "$installer" >/dev/null 2>&1; then
  fail 'installer accepted a default deny key equal to a control key'
fi
printf 'ok - installer enforces unique control/default keys\n'

credential_missing=$workdir/credentials-missing
cp -R "$credential_source" "$credential_missing"
rm -f "$credential_missing/jp/openvpn-user"
credential_missing_root=$workdir/credential-missing-root
mkdir -m 0700 "$credential_missing_root"
if run_installer_inputs "$credential_missing_root" "$installer" \
  "$fixture_source" "$credential_missing" >/dev/null 2>&1; then
  fail 'installer accepted a credential source with a missing file'
fi
[ ! -e "$credential_missing_root/private/2026-07-18.5" ] ||
  fail 'missing credential source published a private tree'
printf 'ok - installer rejects missing credential source files\n'

credential_extra=$workdir/credentials-extra
cp -R "$credential_source" "$credential_extra"
printf '%s\n' 'not-reviewed' >"$credential_extra/uk/extra-secret"
chmod 0600 "$credential_extra/uk/extra-secret"
credential_extra_root=$workdir/credential-extra-root
mkdir -m 0700 "$credential_extra_root"
if run_installer_inputs "$credential_extra_root" "$installer" \
  "$fixture_source" "$credential_extra" >/dev/null 2>&1; then
  fail 'installer accepted an extra credential source file'
fi
printf 'ok - installer enforces exact credential source entries\n'

credential_mode_bad=$workdir/credentials-mode-bad
cp -R "$credential_source" "$credential_mode_bad"
chmod 0644 "$credential_mode_bad/romania/httpproxy-user"
credential_mode_bad_root=$workdir/credential-mode-bad-root
mkdir -m 0700 "$credential_mode_bad_root"
if run_installer_inputs "$credential_mode_bad_root" "$installer" \
  "$fixture_source" "$credential_mode_bad" >/dev/null 2>&1; then
  fail 'installer accepted a group/world-readable credential source file'
fi
printf 'ok - installer rejects unsafe credential source permissions\n'

credential_dir_bad=$workdir/credentials-dir-bad
cp -R "$credential_source" "$credential_dir_bad"
chmod 0770 "$credential_dir_bad/uk"
credential_dir_bad_root=$workdir/credential-dir-bad-root
mkdir -m 0700 "$credential_dir_bad_root"
if run_installer_inputs "$credential_dir_bad_root" "$installer" \
  "$fixture_source" "$credential_dir_bad" >/dev/null 2>&1; then
  fail 'installer accepted a group-writable credential source directory'
fi
printf 'ok - installer rejects unsafe credential source directories\n'

credential_tamper=$workdir/credentials-tamper
cp -R "$credential_source" "$credential_tamper"
credential_tamper_root=$workdir/credential-tamper-root
mkdir -m 0700 "$credential_tamper_root"
run_installer_inputs "$credential_tamper_root" "$installer" \
  "$fixture_source" "$credential_tamper" >/dev/null ||
  fail 'credential tamper fixture setup failed'
chmod 700 "$credential_tamper/jp"
chmod 600 "$credential_tamper/jp/openvpn-password"
printf '%s\n' 'changed-after-publication' >"$credential_tamper/jp/openvpn-password"
chmod 600 "$credential_tamper/jp/openvpn-password"
chmod 500 "$credential_tamper/jp"
if run_installer_inputs "$credential_tamper_root" "$installer" \
  "$fixture_source" "$credential_tamper" >/dev/null 2>&1; then
  fail 'installer accepted a credential source changed after publication'
fi
printf 'ok - installer refuses changed credential sources for an existing version\n'

# A source profile that differs from the reviewed manifest fails before any
# version directory is published.
source_tamper=$workdir/source-tamper
mkdir -m 0700 "$source_tamper"
cp -- "$fixture_source/$jp_name" "$source_tamper/$jp_name"
cp -- "$fixture_source/$ro_name" "$source_tamper/$ro_name"
cp -- "$fixture_source/$uk_name" "$source_tamper/$uk_name"
printf '%s\n' '# tamper' >>"$source_tamper/$jp_name"
source_tamper_root=$workdir/source-tamper-root
mkdir -m 0700 "$source_tamper_root"
if DDNS_VPN_ASSET_ROOT="$source_tamper_root/assets" \
  DDNS_VPN_PRIVATE_ROOT="$source_tamper_root/private" \
  DDNS_VPN_RUNTIME_ROOT="$source_tamper_root/runtime" \
  SURFSHARK_PROFILE_DIR="$source_tamper" \
  DDNS_VPN_CREDENTIAL_SOURCE_DIR="$credential_source" \
  sh "$installer" >/dev/null 2>&1; then
  fail 'installer accepted a source profile that differs from the manifest'
fi
[ ! -e "$source_tamper_root/assets/2026-07-18.5" ] ||
  fail 'failed source validation published an asset tree'
[ ! -e "$source_tamper_root/private/2026-07-18.5" ] ||
  fail 'failed source validation published a private tree'
[ ! -e "$source_tamper_root/runtime/2026-07-18.5" ] ||
  fail 'failed source validation published a runtime tree'
printf 'ok - installer rejects changed source profiles before publication\n'

# Manifest shape is part of the reviewed input.  Test the copied installer so
# the repository's checked-in manifest is never modified by the test.
manifest_fixture=$workdir/repo
mkdir -m 0700 "$manifest_fixture" "$manifest_fixture/scripts" "$manifest_fixture/portainer"
cp -- "$installer" "$manifest_fixture/scripts/install-portainer-assets.sh"
cp -- "$repo_root/scripts/ddns-openvpn.sh" "$manifest_fixture/scripts/ddns-openvpn.sh"
cp -- "$manifest" "$manifest_fixture/portainer/assets-2026-07-18.5.sha256"
printf '%s\n' '0000000000000000000000000000000000000000000000000000000000000000  extra' \
  >>"$manifest_fixture/portainer/assets-2026-07-18.5.sha256"
chmod 0500 "$manifest_fixture/portainer" "$manifest_fixture/scripts"
manifest_bad_root=$workdir/manifest-bad-root
mkdir -m 0700 "$manifest_bad_root"
if run_installer_at "$manifest_bad_root" \
  "$manifest_fixture/scripts/install-portainer-assets.sh" >/dev/null 2>&1; then
  fail 'installer accepted a manifest with an extra asset'
fi
[ ! -e "$manifest_bad_root/assets/2026-07-18.5" ] ||
  fail 'invalid manifest published an asset tree'
printf 'ok - installer rejects an unreviewed manifest\n'

# Existing trust-path permissions and symlinks are fail-closed.
unsafe_parent=$workdir/unsafe-parent
mkdir -m 0770 "$unsafe_parent"
unsafe_root=$unsafe_parent/roots
if run_installer_at "$unsafe_root" "$installer" >/dev/null 2>&1; then
  fail 'installer accepted a group-writable asset ancestor'
fi
symlink_parent=$workdir/symlink-parent
ln -s "$workdir" "$symlink_parent"
symlink_root=$symlink_parent/roots
if run_installer_at "$symlink_root" "$installer" >/dev/null 2>&1; then
  fail 'installer followed a symlinked asset ancestor'
fi
printf 'ok - installer rejects unsafe asset-root permissions and symlinks\n'

printf 'Portainer asset installer tests passed.\n'
