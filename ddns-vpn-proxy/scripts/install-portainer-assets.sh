#!/bin/sh
set -eu

# Publish the reviewed helper and VPN profiles, plus per-region host-generated
# control credentials, secret files, and a narrowly scoped writable resolver
# file, into versioned directories for the Portainer stack.  The trees are
# staged on their respective filesystems and renamed into place with mv(1); an
# existing version is never replaced.

umask 077

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
asset_version=2026-07-18.5
asset_parent=${DDNS_VPN_ASSET_ROOT:-/home/df/.local/share/ddns-vpn-proxy/assets}
private_parent=${DDNS_VPN_PRIVATE_ROOT:-/home/df/.local/share/ddns-vpn-proxy/private}
runtime_parent=${DDNS_VPN_RUNTIME_ROOT:-/home/df/.local/share/ddns-vpn-proxy/runtime}
profile_source=${SURFSHARK_PROFILE_DIR:-/mnt/appdata/gluetun/surfshark-ovpn}
credential_source=${DDNS_VPN_CREDENTIAL_SOURCE_DIR:-/home/df/.config/ddns-vpn-proxy/credentials}
manifest=$repo_root/portainer/assets-$asset_version.sha256
asset_target=$asset_parent/$asset_version
private_target=$private_parent/$asset_version
runtime_target=$runtime_parent/$asset_version
asset_staging=
private_staging=
runtime_staging=
manifest_snapshot=

helper_source=$repo_root/scripts/ddns-openvpn.sh
jp_name=jp-tok.prod.surfshark.com_udp.ovpn
ro_name=ro-buc.prod.surfshark.com_udp.ovpn
uk_name=uk-lon.prod.surfshark.com_udp.ovpn
region_names='jp romania uk'
credential_names='openvpn-user openvpn-password httpproxy-user httpproxy-password shadowsocks-password'

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  # Staging directories are owner-only.  Restore owner write permission before
  # removing them; errors here must not mask the original failure.
  if [ -n "$asset_staging" ] && { [ -d "$asset_staging" ] || [ -L "$asset_staging" ]; }; then
    chmod -R u+rwX -- "$asset_staging" 2>/dev/null || :
    rm -rf -- "$asset_staging" || :
  fi
  if [ -n "$private_staging" ] && { [ -d "$private_staging" ] || [ -L "$private_staging" ]; }; then
    chmod -R u+rwX -- "$private_staging" 2>/dev/null || :
    rm -rf -- "$private_staging" || :
  fi
  if [ -n "$runtime_staging" ] && { [ -d "$runtime_staging" ] || [ -L "$runtime_staging" ]; }; then
    chmod -R u+rwX -- "$runtime_staging" 2>/dev/null || :
    rm -rf -- "$runtime_staging" || :
  fi
  if [ -n "$manifest_snapshot" ] && [ -e "$manifest_snapshot" ]; then
    rm -f -- "$manifest_snapshot" || :
  fi
  return 0
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

for command_name in \
  awk chmod cmp dirname find install mktemp mv od rm sha256sum sort stat sed tr wc
do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "required command not found: $command_name"
done

path_is_safe() {
  path=$1
  case $path in
    /*) ;;
    *) return 1 ;;
  esac
  case $path in
    /) ;;
    *[!A-Za-z0-9_./-]*|*//*|*/|*/../*|*/..|*/./*|*/.) return 1 ;;
  esac
  return 0
}

check_no_group_world_write() {
  permission_path=$1
  permissions=$(stat -c '%A' "$permission_path") || return 1
  # %A is ten characters: type, owner rwx, group rwx, other rwx.  Reject
  # group-write (position 6) and other-write (position 9) explicitly.
  case $permissions in
    ?????w*|????????w*) return 1 ;;
  esac
  return 0
}

check_real_directory() {
  real_directory_path=$1
  [ -d "$real_directory_path" ] && [ ! -L "$real_directory_path" ] || return 1
  check_no_group_world_write "$real_directory_path"
}

verify_secure_ancestors() {
  ancestor_path=$1
  path_is_safe "$ancestor_path" || return 1
  check_real_directory / || return 1

  old_ifs=$IFS
  IFS=/
  # Paths are restricted to a safe character set above, so field splitting is
  # deterministic and cannot expand user-controlled glob characters.
  # shellcheck disable=SC2086 # path_is_safe disables glob characters first.
  set -- $ancestor_path
  IFS=$old_ifs
  current=/
  for component
  do
    [ -n "$component" ] || continue
    current=$current$component
    [ -e "$current" ] && [ ! -L "$current" ] || return 1
    check_real_directory "$current" || return 1
    current=$current/
  done
  return 0
}

ensure_directory_tree() {
  directory=$1
  path_is_safe "$directory" || die "directory path is invalid: $directory"
  check_real_directory / || die 'root directory is missing, symlinked, or group/world writable'

  old_ifs=$IFS
  IFS=/
  # shellcheck disable=SC2086 # path_is_safe disables glob characters first.
  set -- $directory
  IFS=$old_ifs
  current=/
  for component
  do
    [ -n "$component" ] || continue
    current=$current$component
    if [ -L "$current" ]; then
      die "directory component is a symlink: $current"
    fi
    if [ -e "$current" ]; then
      [ -d "$current" ] || die "directory component is not a directory: $current"
    else
      install -d -m 0700 -- "$current" || die "failed to create directory: $current"
    fi
    check_no_group_world_write "$current" ||
      die "directory is group/world writable: $current"
    current=$current/
  done
}

regular_file() {
  checked_file=$1
  [ -f "$checked_file" ] && [ ! -L "$checked_file" ]
}

immutable_file() {
  immutable_path=$1
  regular_file "$immutable_path" || return 1
  [ "$(stat -c '%h' "$immutable_path")" = 1 ]
}

sha256_file() {
  hash_line=$(sha256sum "$1") || return 1
  printf '%s\n' "${hash_line%% *}"
}

manifest_hash() {
  wanted_path=$1
  awk -v wanted="$wanted_path" '$2 == wanted { print $1; found++ } END { exit(found == 1 ? 0 : 1) }' \
    "$manifest_snapshot"
}

validate_manifest() {
  regular_file "$manifest" || die "reviewed checksum manifest is missing or a symlink: $manifest"
  manifest_snapshot=$(mktemp "${TMPDIR:-/tmp}/ddns-vpn-manifest.XXXXXX") ||
    die 'failed to create manifest snapshot'
  install -m 0600 -- "$manifest" "$manifest_snapshot" ||
    die 'failed to snapshot reviewed checksum manifest'

  awk '
    NF != 2 || length($1) != 64 || $1 !~ /^[0-9a-f]+$/ { exit 1 }
  ' "$manifest_snapshot" || die 'reviewed checksum manifest has an invalid line'

  [ "$(wc -l <"$manifest_snapshot")" -eq 4 ] ||
    die 'reviewed checksum manifest must contain exactly four assets'

  manifest_paths=$(awk '{ print $2 }' "$manifest_snapshot") ||
    die 'failed to read reviewed checksum manifest'
  expected_paths=$(printf '%s\n' \
    ddns-openvpn.sh \
    profiles/$jp_name \
    profiles/$ro_name \
    profiles/$uk_name)
  [ "$manifest_paths" = "$expected_paths" ] ||
    die 'reviewed checksum manifest contains an unexpected asset path'
}

validate_source_file() {
  source_file=$1
  [ -f "$source_file" ] && [ ! -L "$source_file" ] ||
    die "asset source is missing, not regular, or a symlink: $source_file"
}

validate_credential_file() {
  credential_file=$1
  credential_name=$2
  regular_file "$credential_file" ||
    die "credential source is missing, not regular, or a symlink: $credential_name"
  credential_mode=$(stat -c '%a' "$credential_file") ||
    die "failed to inspect credential source permissions: $credential_name"
  case $credential_mode in
    400|600) ;;
    *) die "credential source must be mode 0400 or 0600: $credential_name" ;;
  esac
  credential_bytes=$(stat -c '%s' "$credential_file") ||
    die "failed to size credential source: $credential_name"
  [ "$credential_bytes" -le 4097 ] ||
    die "credential source is too long: $credential_name"
  od -v -An -tu1 "$credential_file" | awk '
    {
      for (field = 1; field <= NF; field++) {
        byte = $field + 0
        if (byte == 10) {
          newlines++
        } else {
          if (byte < 32 || byte == 127) exit 1
          payload++
        }
        last = byte
      }
    }
    END {
      if (payload == 0 || newlines != 1 || last != 10) exit 1
    }
  ' || die "credential source must be one non-empty line without control characters: $credential_name"
}

assert_credential_source_root_entries() {
  actual_entries=$(find "$credential_source" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort) || return 1
  expected_entries=$(printf '%s\n' \
    "$credential_source/jp" \
    "$credential_source/romania" \
    "$credential_source/uk" | LC_ALL=C sort)
  [ "$actual_entries" = "$expected_entries" ]
}

assert_credential_region_entries() {
  credential_region=$1
  actual_entries=$(find "$credential_region" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort) || return 1
  expected_entries=$(printf '%s\n' \
    "$credential_region/openvpn-user" \
    "$credential_region/openvpn-password" \
    "$credential_region/httpproxy-user" \
    "$credential_region/httpproxy-password" \
    "$credential_region/shadowsocks-password" | LC_ALL=C sort)
  [ "$actual_entries" = "$expected_entries" ]
}

verify_hash_against_manifest() {
  source_file=$1
  reviewed_path=$2
  reviewed_hash=$(manifest_hash "$reviewed_path") ||
    die "manifest hash is missing: $reviewed_path"
  actual_hash=$(sha256_file "$source_file") ||
    die "failed to hash asset source: $source_file"
  [ "$actual_hash" = "$reviewed_hash" ] ||
    die "asset does not match reviewed hash: $reviewed_path"
}

assert_asset_entries() {
  checked_root=$1
  actual_entries=$(find "$checked_root" -mindepth 1 -maxdepth 2 -print | LC_ALL=C sort) || return 1
  expected_entries=$(printf '%s\n' \
    "$checked_root/ddns-openvpn.sh" \
    "$checked_root/profiles" \
    "$checked_root/profiles/$jp_name" \
    "$checked_root/profiles/$ro_name" \
    "$checked_root/profiles/$uk_name" | LC_ALL=C sort)
  [ "$actual_entries" = "$expected_entries" ]
}

verify_asset_tree() {
  checked_root=$1
  check_real_directory "$checked_root" || return 1
  [ "$(stat -c '%a' "$checked_root")" = 500 ] || return 1
  check_real_directory "$checked_root/profiles" || return 1
  [ "$(stat -c '%a' "$checked_root/profiles")" = 500 ] || return 1
  assert_asset_entries "$checked_root" || return 1

  for relative_path in \
    ddns-openvpn.sh \
    profiles/$jp_name \
    profiles/$ro_name \
    profiles/$uk_name
  do
    immutable_file "$checked_root/$relative_path" || return 1
    [ "$(stat -c '%a' "$checked_root/$relative_path")" = 400 ] || return 1
  done
  (
    CDPATH='' cd -- "$checked_root"
    sha256sum -c "$manifest_snapshot" >/dev/null
  )
}

read_api_key() {
  key_file=$1
  immutable_file "$key_file" || return 1
  [ "$(stat -c '%a' "$key_file")" = 400 ] || return 1
  [ "$(wc -l <"$key_file")" -eq 1 ] || return 1
  [ "$(wc -c <"$key_file")" -eq 65 ] || return 1
  key_value=$(sed -n '1p' "$key_file") || return 1
  case $key_value in
    ''|*[!0-9a-f]*) return 1 ;;
  esac
  [ "${#key_value}" -eq 64 ] || return 1
  printf '%s\n' "$key_value"
}

auth_hash_for_key() {
  auth_key=$1
  {
    printf '%s\n' '[[roles]]'
    printf '%s\n' 'name = "ddns-watcher"'
    printf '%s\n' 'auth = "apikey"'
    printf 'apikey = "%s"\n' "$auth_key"
    printf '%s\n' 'routes = ["PUT /v1/vpn/status"]'
  } | sha256sum | awk '{ print $1 }'
}

default_role_hash_for_key() {
  default_key=$1
  printf '{"name":"deny-default","auth":"apikey","apikey":"%s"}\n' "$default_key" |
    sha256sum | awk '{ print $1 }'
}

read_default_role_key() {
  role_file=$1
  immutable_file "$role_file" || return 1
  [ "$(stat -c '%a' "$role_file")" = 400 ] || return 1
  [ "$(wc -l <"$role_file")" -eq 1 ] || return 1
  [ -z "$(sed -n '2p' "$role_file")" ] || return 1
  role_line=$(sed -n '1p' "$role_file") || return 1
  role_key=$(printf '%s\n' "$role_line" |
    sed -n 's/^{"name":"deny-default","auth":"apikey","apikey":"\([0-9a-f]*\)"}$/\1/p')
  case $role_key in
    ''|*[!0-9a-f]*) return 1 ;;
  esac
  [ "${#role_key}" -eq 64 ] || return 1
  printf '%s\n' "$role_key"
}

record_unique_key() {
  candidate_key=$1
  for prior_key in $seen_keys
  do
    [ "$prior_key" != "$candidate_key" ] || return 1
  done
  seen_keys="$seen_keys $candidate_key"
  return 0
}

verify_private_region() {
  private_root=$1
  region_name=$2
  region_root=$private_root/$region_name
  check_real_directory "$region_root" || return 1
  [ "$(stat -c '%a' "$region_root")" = 500 ] || return 1

  actual_entries=$(find "$region_root" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort) || return 1
  expected_entries=$(printf '%s\n' \
    "$region_root/control-api-key" \
    "$region_root/control-auth.toml" \
    "$region_root/control-default-role.json" \
    "$region_root/openvpn-user" \
    "$region_root/openvpn-password" \
    "$region_root/httpproxy-user" \
    "$region_root/httpproxy-password" \
    "$region_root/shadowsocks-password" | LC_ALL=C sort)
  [ "$actual_entries" = "$expected_entries" ] || return 1

  control_key=$(read_api_key "$region_root/control-api-key") || return 1
  record_unique_key "$control_key" || return 1
  immutable_file "$region_root/control-auth.toml" || return 1
  [ "$(stat -c '%a' "$region_root/control-auth.toml")" = 400 ] || return 1
  actual_auth_hash=$(sha256_file "$region_root/control-auth.toml") || return 1
  expected_auth_hash=$(auth_hash_for_key "$control_key") || return 1
  [ "$actual_auth_hash" = "$expected_auth_hash" ] || return 1

  default_key=$(read_default_role_key "$region_root/control-default-role.json") || return 1
  record_unique_key "$default_key" || return 1
  actual_default_hash=$(sha256_file "$region_root/control-default-role.json") || return 1
  expected_default_hash=$(default_role_hash_for_key "$default_key") || return 1
  [ "$actual_default_hash" = "$expected_default_hash" ] || return 1

  for credential_name in $credential_names
  do
    immutable_file "$region_root/$credential_name" || return 1
    [ "$(stat -c '%a' "$region_root/$credential_name")" = 400 ] || return 1
    cmp -s "$credential_source/$region_name/$credential_name" \
      "$region_root/$credential_name" || return 1
  done
  return 0
}

verify_private_tree() {
  checked_root=$1
  check_real_directory "$checked_root" || return 1
  [ "$(stat -c '%a' "$checked_root")" = 500 ] || return 1
  actual_entries=$(find "$checked_root" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort) || return 1
  expected_entries=$(printf '%s\n' \
    "$checked_root/jp" \
    "$checked_root/romania" \
    "$checked_root/uk" | LC_ALL=C sort)
  [ "$actual_entries" = "$expected_entries" ] || return 1

  seen_keys=
  for region_name in $region_names
  do
    verify_private_region "$checked_root" "$region_name" || return 1
  done
  return 0
}

assert_runtime_entries() {
  checked_root=$1
  actual_entries=$(find "$checked_root" -mindepth 1 -maxdepth 2 -print | LC_ALL=C sort) || return 1
  expected_entries=$(printf '%s\n' \
    "$checked_root/jp" "$checked_root/romania" "$checked_root/uk" \
    "$checked_root/jp/resolv.conf" \
    "$checked_root/romania/resolv.conf" \
    "$checked_root/uk/resolv.conf" | LC_ALL=C sort)
  [ "$actual_entries" = "$expected_entries" ]
}

verify_runtime_tree() {
  checked_root=$1
  check_real_directory "$checked_root" || return 1
  [ "$(stat -c '%a' "$checked_root")" = 500 ] || return 1
  assert_runtime_entries "$checked_root" || return 1
  for region_name in $region_names
  do
    region_root=$checked_root/$region_name
    check_real_directory "$region_root" || return 1
    [ "$(stat -c '%a' "$region_root")" = 500 ] || return 1
    immutable_file "$region_root/resolv.conf" || return 1
    [ "$(stat -c '%a' "$region_root/resolv.conf")" = 600 ] || return 1
    [ "$(stat -c '%u:%g' "$region_root/resolv.conf")" = 1000:1000 ] || return 1
    [ "$(wc -l <"$region_root/resolv.conf")" -eq 1 ] || return 1
    [ "$(sed -n '1p' "$region_root/resolv.conf")" = 'nameserver 127.0.0.1' ] || return 1
  done
  return 0
}

generate_api_key() {
  # -v disables od's duplicate-line compression; a compressed '*' would not
  # be valid hexadecimal if the random stream happens to repeat a line.
  random_octets=$(od -v -An -tx1 -N32 /dev/urandom) || return 1
  generated_key=$(printf '%s\n' "$random_octets" | tr -d '[:space:]') || return 1
  case $generated_key in
    ''|*[!0-9a-f]*) return 1 ;;
  esac
  [ "${#generated_key}" -eq 64 ] || return 1
  printf '%s\n' "$generated_key"
}

generate_unique_api_key() {
  unique_attempts=0
  while [ "$unique_attempts" -lt 128 ]
  do
    unique_attempts=$((unique_attempts + 1))
    candidate_key=$(generate_api_key) || return 1
    if record_unique_key "$candidate_key"; then
      generated_unique_key=$candidate_key
      return 0
    fi
  done
  return 1
}

write_control_auth() {
  auth_key=$1
  auth_file=$2
  {
    printf '%s\n' '[[roles]]'
    printf '%s\n' 'name = "ddns-watcher"'
    printf '%s\n' 'auth = "apikey"'
    printf 'apikey = "%s"\n' "$auth_key"
    printf '%s\n' 'routes = ["PUT /v1/vpn/status"]'
  } >"$auth_file" || return 1
  chmod 0400 -- "$auth_file"
}

stage_asset_tree() {
  asset_staging=$(mktemp -d "$asset_parent/.${asset_version}.asset.XXXXXX") ||
    die 'failed to create asset staging directory'
  install -d -m 0700 -- "$asset_staging/profiles" ||
    die 'failed to create profile staging directory'
  install -m 0400 -- "$helper_source" "$asset_staging/ddns-openvpn.sh" ||
    die 'failed to stage helper'
  install -m 0400 -- "$profile_source/$jp_name" \
    "$asset_staging/profiles/$jp_name" || die 'failed to stage JP profile'
  install -m 0400 -- "$profile_source/$ro_name" \
    "$asset_staging/profiles/$ro_name" || die 'failed to stage Romania profile'
  install -m 0400 -- "$profile_source/$uk_name" \
    "$asset_staging/profiles/$uk_name" || die 'failed to stage UK profile'

  (
    CDPATH='' cd -- "$asset_staging"
    sha256sum -c "$manifest_snapshot" >/dev/null
  ) || die 'staged assets do not match the reviewed checksum manifest'
  chmod 0500 -- "$asset_staging/profiles" "$asset_staging" ||
    die 'failed to make asset tree immutable'
}

stage_private_tree() {
  private_staging=$(mktemp -d "$private_parent/.${asset_version}.private.XXXXXX") ||
    die 'failed to create private staging directory'
  for region_name in $region_names
  do
    install -d -m 0700 -- "$private_staging/$region_name" ||
      die "failed to create private region staging directory: $region_name"
  done
  seen_keys=
  for region_name in $region_names
  do
    region_staging=$private_staging/$region_name
    generate_unique_api_key || die "failed to generate control API key: $region_name"
    control_key=$generated_unique_key
    printf '%s\n' "$control_key" >"$region_staging/control-api-key" ||
      die "failed to write control API key: $region_name"
    chmod 0400 -- "$region_staging/control-api-key" ||
      die "failed to protect control API key: $region_name"
    write_control_auth "$control_key" "$region_staging/control-auth.toml" ||
      die "failed to write control API auth configuration: $region_name"

    generate_unique_api_key || die "failed to generate default role key: $region_name"
    default_key=$generated_unique_key
    printf '{"name":"deny-default","auth":"apikey","apikey":"%s"}\n' \
      "$default_key" >"$region_staging/control-default-role.json" ||
      die "failed to write default role: $region_name"
    chmod 0400 -- "$region_staging/control-default-role.json" ||
      die "failed to protect default role: $region_name"

    for credential_name in $credential_names
    do
      install -m 0400 -- "$credential_source/$region_name/$credential_name" \
        "$region_staging/$credential_name" ||
        die "failed to stage credential: $region_name/$credential_name"
      cmp -s "$credential_source/$region_name/$credential_name" \
        "$region_staging/$credential_name" ||
        die "staged credential does not match source: $region_name/$credential_name"
    done
    chmod 0500 -- "$region_staging" ||
      die "failed to make private region immutable: $region_name"
  done
  chmod 0500 -- "$private_staging" ||
    die 'failed to make private tree immutable'
  verify_private_tree "$private_staging" ||
    die 'private staging tree failed integrity verification'
}

stage_runtime_tree() {
  runtime_staging=$(mktemp -d "$runtime_parent/.${asset_version}.runtime.XXXXXX") ||
    die 'failed to create runtime staging directory'
  for region_name in $region_names
  do
    install -d -m 0700 -- "$runtime_staging/$region_name" ||
      die "failed to create runtime region staging directory: $region_name"
    printf '%s\n' 'nameserver 127.0.0.1' >"$runtime_staging/$region_name/resolv.conf" ||
      die "failed to write runtime resolver file: $region_name"
    chmod 0600 -- "$runtime_staging/$region_name/resolv.conf" ||
      die "failed to protect runtime resolver file: $region_name"
    chmod 0500 -- "$runtime_staging/$region_name" ||
      die "failed to protect runtime region directory: $region_name"
  done
  chmod 0500 -- "$runtime_staging" || die 'failed to protect runtime tree'
  verify_runtime_tree "$runtime_staging" || die 'runtime staging tree failed integrity verification'
}

# The production contract is rooted under /home/df.  Check every existing
# ancestor before creating any child; this rejects symlink traversal and any
# group/world-writable directory in the trust path.
verify_secure_ancestors /home/df ||
  die 'the /home/df trust path is missing, symlinked, or group/world writable'

path_is_safe "$asset_parent" || die "asset root path is invalid: $asset_parent"
path_is_safe "$private_parent" || die "private root path is invalid: $private_parent"
path_is_safe "$runtime_parent" || die "runtime root path is invalid: $runtime_parent"
[ "$asset_parent" != / ] && [ "$private_parent" != / ] ||
  die 'asset and private roots must not be the filesystem root'
[ "$runtime_parent" != / ] || die 'runtime root must not be the filesystem root'
[ "$asset_parent" != "$private_parent" ] ||
  die 'asset and private roots must be different directories'
[ "$asset_parent" != "$runtime_parent" ] && [ "$private_parent" != "$runtime_parent" ] ||
  die 'asset, private, and runtime roots must be different directories'
case "$private_parent/" in
  "$asset_target/"*) die 'private root must not be inside the asset version directory' ;;
esac
case "$asset_parent/" in
  "$private_target/"*) die 'asset root must not be inside the private version directory' ;;
esac
case "$runtime_parent/" in
  "$asset_target/"*|"$private_target/"*) die 'runtime root must not be inside an immutable version directory' ;;
esac
case "$asset_parent/" in
  "$runtime_target/"*) die 'asset root must not be inside the runtime version directory' ;;
esac
case "$private_parent/" in
  "$runtime_target/"*) die 'private root must not be inside the runtime version directory' ;;
esac
path_is_safe "$credential_source" ||
  die "credential source path is invalid: $credential_source"

validate_manifest

validate_source_file "$helper_source"
[ -d "$profile_source" ] && [ ! -L "$profile_source" ] ||
  die "profile source must be a real directory, not a symlink: $profile_source"
validate_source_file "$profile_source/$jp_name"
validate_source_file "$profile_source/$ro_name"
validate_source_file "$profile_source/$uk_name"
verify_hash_against_manifest "$helper_source" ddns-openvpn.sh
verify_hash_against_manifest "$profile_source/$jp_name" profiles/$jp_name
verify_hash_against_manifest "$profile_source/$ro_name" profiles/$ro_name
verify_hash_against_manifest "$profile_source/$uk_name" profiles/$uk_name

verify_secure_ancestors "$credential_source" ||
  die 'credential source trust path is missing, symlinked, or group/world writable'
assert_credential_source_root_entries ||
  die 'credential source root must contain exactly the jp, romania and uk directories'
for region_name in $region_names
do
  credential_region_source=$credential_source/$region_name
  verify_secure_ancestors "$credential_region_source" ||
    die "credential region trust path is missing, symlinked, or group/world writable: $region_name"
  assert_credential_region_entries "$credential_region_source" ||
    die "credential region must contain exactly the five reviewed secret files: $region_name"
  for credential_name in $credential_names
  do
    validate_credential_file "$credential_region_source/$credential_name" \
      "$region_name/$credential_name"
  done
done

ensure_directory_tree "$asset_parent"
ensure_directory_tree "$private_parent"
ensure_directory_tree "$runtime_parent"

asset_exists=0
private_exists=0
runtime_exists=0
if [ -e "$asset_target" ] || [ -L "$asset_target" ]; then
  asset_exists=1
  verify_asset_tree "$asset_target" ||
    die "existing asset version failed integrity or permission checks; refusing overwrite: $asset_target"
fi
if [ -e "$private_target" ] || [ -L "$private_target" ]; then
  private_exists=1
  verify_private_tree "$private_target" ||
    die "existing private version failed integrity or permission checks; refusing overwrite: $private_target"
fi
if [ -e "$runtime_target" ] || [ -L "$runtime_target" ]; then
  runtime_exists=1
  verify_runtime_tree "$runtime_target" ||
    die "existing runtime version failed integrity or permission checks; refusing overwrite: $runtime_target"
fi

[ "$asset_exists" -eq 1 ] || stage_asset_tree
[ "$private_exists" -eq 1 ] || stage_private_tree
[ "$runtime_exists" -eq 1 ] || stage_runtime_tree

# Recheck the publication points immediately before each rename.  mv -T keeps
# the operation a single directory rename and cannot merge into a raced target.
if [ "$asset_exists" -eq 0 ]; then
  [ ! -e "$asset_target" ] && [ ! -L "$asset_target" ] ||
    die "asset target appeared during installation; refusing overwrite: $asset_target"
  verify_asset_tree "$asset_staging" ||
    die 'asset staging tree changed before publication'
  mv -T -- "$asset_staging" "$asset_target" || die 'failed to publish asset tree'
  asset_staging=
fi
if [ "$private_exists" -eq 0 ]; then
  [ ! -e "$private_target" ] && [ ! -L "$private_target" ] ||
    die "private target appeared during installation; refusing overwrite: $private_target"
  verify_private_tree "$private_staging" ||
    die 'private staging tree or credential source changed before publication'
  mv -T -- "$private_staging" "$private_target" || die 'failed to publish private tree'
  private_staging=
fi
if [ "$runtime_exists" -eq 0 ]; then
  [ ! -e "$runtime_target" ] && [ ! -L "$runtime_target" ] ||
    die "runtime target appeared during installation; refusing overwrite: $runtime_target"
  verify_runtime_tree "$runtime_staging" ||
    die 'runtime staging tree changed before publication'
  mv -T -- "$runtime_staging" "$runtime_target" || die 'failed to publish runtime tree'
  runtime_staging=
fi

verify_asset_tree "$asset_target" ||
  die "published asset tree failed integrity verification: $asset_target"
verify_private_tree "$private_target" ||
  die "published private tree failed integrity verification: $private_target"
verify_runtime_tree "$runtime_target" ||
  die "published runtime tree failed integrity verification: $runtime_target"

printf 'Verified Portainer assets: %s\n' "$asset_target"
printf 'Verified regional private credentials: %s\n' "$private_target"
printf 'Verified regional resolver runtime files: %s\n' "$runtime_target"
