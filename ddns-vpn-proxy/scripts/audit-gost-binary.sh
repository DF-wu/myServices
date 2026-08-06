#!/bin/sh
set -eu

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

assert_dependency() {
  module=$1
  expected=$2
  actual=$(awk -v module="$module" '$1 == "dep" && $2 == module { print $3 }' "$build_info")
  [ "$actual" = "$expected" ] ||
    die "$module version mismatch: expected $expected, found ${actual:-missing}"
}

assert_build_setting() {
  setting=$1
  expected=$2
  actual=$(awk -v setting="$setting" '
    $1 == "build" {
      split($2, parts, "=")
      if (parts[1] == setting) print parts[2]
    }
  ' "$build_info")
  [ "$actual" = "$expected" ] ||
    die "$setting build setting mismatch: expected $expected, found ${actual:-missing}"
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] ||
  die 'usage: audit-gost-binary.sh BINARY [OPENVEX_FILE]'

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
binary=$1
vex_file=${2:-$repo_root/security/gost-go-2026-5932.openvex.json}
govulncheck=${GOVULNCHECK:-govulncheck}

require_command go
require_command jq
require_command sha256sum
require_command strings
require_command awk
require_command grep
require_command "$govulncheck"

[ -f "$binary" ] || die "GOST binary not found: $binary"
[ -r "$binary" ] || die "GOST binary is not readable: $binary"
[ -f "$vex_file" ] || die "OpenVEX file not found: $vex_file"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/gost-audit.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
build_info=$tmp_dir/build-info.txt
nm_output=$tmp_dir/nm.txt
strings_output=$tmp_dir/strings.txt
govuln_output=$tmp_dir/govuln.json

binary_sha=$(sha256sum "$binary" | awk '{ print $1 }')

jq -e --arg binary_sha "$binary_sha" '
  .["@context"] == "https://openvex.dev/ns/v0.2.0" and
  .["@id"] == "https://github.com/DF-wu/myServices/security/vex/gost-go-2026-5932" and
  .author == "DF-wu/myServices maintainers" and
  .role == "Project Maintainer" and
  .version == 1 and
  (.statements | length) == 1 and
  (
    .statements[0] as $statement |
    $statement.vulnerability.name == "GO-2026-5932" and
    $statement.vulnerability["@id"] == "https://pkg.go.dev/vuln/GO-2026-5932" and
    $statement.status == "not_affected" and
    $statement.justification == "vulnerable_code_not_present" and
    ($statement.products | length) == 2 and
    all($statement.products[];
      .["@id"] == "pkg:golang/github.com/go-gost/gost" and
      (.hashes | keys) == ["sha-256"] and
      (.hashes["sha-256"] | test("^[0-9a-f]{64}$")) and
      .subcomponents == [
        {"@id": "pkg:golang/golang.org/x/crypto@v0.53.0"}
      ]
    ) and
    ([$statement.products[].hashes["sha-256"]] | unique | length) == 2 and
    any($statement.products[]; .hashes["sha-256"] == $binary_sha)
  )
' "$vex_file" >/dev/null ||
  die "OpenVEX scope or binary SHA-256 does not match the reviewed GOST artifacts ($binary_sha)"

go version -m "$binary" >"$build_info" || die 'unable to read Go build information'
[ "$(awk 'NR == 1 { print $NF }' "$build_info")" = go1.26.5 ] ||
  die 'GOST was not built with Go 1.26.5'
[ "$(awk '$1 == "path" { print $2 }' "$build_info")" = github.com/go-gost/gost/cmd/gost ] ||
  die 'unexpected GOST main package'
[ "$(awk '$1 == "mod" { print $2 }' "$build_info")" = github.com/go-gost/gost ] ||
  die 'unexpected GOST main module'
assert_build_setting CGO_ENABLED 0
assert_build_setting GOOS linux
assert_build_setting -trimpath true
architecture=$(awk '$1 == "build" && $2 ~ /^GOARCH=/ { sub(/^GOARCH=/, "", $2); print $2 }' "$build_info")
case "$architecture" in
  amd64 | arm64) ;;
  *) die "GOST architecture must be amd64 or arm64, found ${architecture:-missing}" ;;
esac
assert_dependency golang.org/x/crypto v0.53.0
assert_dependency golang.org/x/net v0.56.0
assert_dependency golang.org/x/text v0.39.0

go tool nm "$binary" >"$nm_output" || die 'unable to inspect the GOST symbol table'
[ -s "$nm_output" ] || die 'GOST symbol table is empty'
grep -Fq 'golang.org/x/crypto/ssh.' "$nm_output" ||
  die 'expected linked x/crypto symbols are missing from GOST'
if grep -Eq 'golang\.org/x/crypto/openpgp([./]|$)' "$nm_output"; then
  die 'golang.org/x/crypto/openpgp is linked into GOST'
fi

strings -a "$binary" >"$strings_output"
if grep -Eq 'golang\.org/x/crypto/openpgp([/[:space:]]|$)' "$strings_output"; then
  die 'golang.org/x/crypto/openpgp is present in GOST printable data'
fi

"$govulncheck" -json -mode=binary "$binary" >"$govuln_output" ||
  die 'govulncheck reported a reachable vulnerability or failed'

jq -s -e '
  ([.[] | select(.config != null) | .config] | length) == 1 and
  ([.[] | select(.config != null) | .config][0] |
    .scanner_name == "govulncheck" and
    .scanner_version == "v1.6.0" and
    .scan_level == "symbol" and
    .scan_mode == "binary"
  ) and
  ([.[] | select(.finding != null) | .finding] == [
    {
      "osv": "GO-2026-5932",
      "trace": [
        {
          "module": "golang.org/x/crypto",
          "version": "v0.53.0"
        }
      ]
    }
  ]) and
  (
    [.[] | select(.osv.id == "GO-2026-5932") | .osv] as $advisories |
    ($advisories | length) == 1 and
    ([$advisories[0].affected[] |
      select(.package.ecosystem == "Go" and .package.name == "golang.org/x/crypto") |
      .ecosystem_specific.imports[].path] | sort) == [
        "golang.org/x/crypto/openpgp",
        "golang.org/x/crypto/openpgp/armor",
        "golang.org/x/crypto/openpgp/clearsign",
        "golang.org/x/crypto/openpgp/elgamal",
        "golang.org/x/crypto/openpgp/errors",
        "golang.org/x/crypto/openpgp/packet",
        "golang.org/x/crypto/openpgp/s2k"
      ]
  )
' "$govuln_output" >/dev/null ||
  die 'govulncheck evidence is broader or different from the reviewed module-only GO-2026-5932 finding'

printf 'GOST binary audit passed: sha256:%s (%s)\n' "$binary_sha" "$architecture"
