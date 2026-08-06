#!/bin/sh
set -eu

# Validate the exact release binaries before allowing the narrow OpenVEX
# statement to be supplied to a vulnerability scanner.

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
vex_file=$repo_root/security/gluetun-go-2026-5932.openvex.json
expected_product='pkg:golang/github.com/qdm12/gluetun'
expected_subcomponent='pkg:golang/golang.org/x/crypto@v0.53.0'
expected_amd64_sha=ce96a5240795bdbc663fef6c1f1a211c92dbe8c32c3576a8532e0818da7b448c
expected_arm64_sha=1007a1fc6c0b8286dff959ee3f25242e8994c7022ba28be6886e1d74126dbe7c
expected_go_mod_sha=f241ee1705ef1e67c85ede7293b3ddefcef507339d9c35fa77bd590fe1d0ec9d
expected_go_sum_sha=b977d62c1dac433506e6dd61d37c1e9214c8610d7602314684fa7afb3a2cd383
expected_impact='The affected golang.org/x/crypto/openpgp package family is absent from both reviewed binaries. OpenPGP symbols in the binaries belong only to the separately maintained github.com/ProtonMail/go-crypto fork.'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

file_sha256() {
  hash_line=$(sha256sum "$1") || return 1
  printf '%s\n' "${hash_line%% *}"
}

read_build_setting() {
  setting_name=$1
  LC_ALL=C awk -F '\t' -v prefix="$setting_name=" '
    $2 == "build" && index($3, prefix) == 1 {
      count++
      value = substr($3, length(prefix) + 1)
    }
    END {
      if (count != 1) exit 1
      print value
    }
  ' "$tmpdir/buildinfo"
}

[ "$#" -eq 2 ] ||
  die "usage: $0 GLUETUN_BINARY GLUETUN_SOURCE_DIR"
binary=$1
source_root=$2

for command_name in awk dirname go govulncheck grep jq mktemp rm sed sha256sum strings
do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "required command not found: $command_name"
done

[ -f "$binary" ] && [ ! -L "$binary" ] && [ -x "$binary" ] ||
  die 'Gluetun binary is missing, symlinked, or not executable'
[ -d "$source_root" ] && [ ! -L "$source_root" ] ||
  die 'Gluetun source directory is missing or symlinked'
[ -f "$vex_file" ] && [ ! -L "$vex_file" ] ||
  die 'Gluetun OpenVEX document is missing or symlinked'
for source_file in go.mod go.sum cmd/gluetun/main.go
do
  [ -f "$source_root/$source_file" ] && [ ! -L "$source_root/$source_file" ] ||
    die "Gluetun source file is missing or symlinked: $source_file"
done

# Keep this statement scoped to one advisory, one root product identity, two
# reviewed architecture hashes, and one exact subcomponent. Extra statements,
# products, aliases, or subcomponents fail validation.
jq -e \
  --arg product "$expected_product" \
  --arg subcomponent "$expected_subcomponent" \
  --arg amd64_sha "$expected_amd64_sha" \
  --arg arm64_sha "$expected_arm64_sha" \
  --arg impact "$expected_impact" '
    type == "object" and
    (keys == ["@context", "@id", "author", "role", "statements", "timestamp", "version"]) and
    .["@context"] == "https://openvex.dev/ns/v0.2.0" and
    .["@id"] == "https://github.com/DF-wu/myServices/security/gluetun-go-2026-5932/v1" and
    .author == "DF-wu/myServices maintainers" and
    .role == "Project Maintainer" and
    (.timestamp | type == "string") and
    (.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    .version == 1 and
    (.statements | type == "array" and length == 1) and
    (.statements[0] | keys == ["impact_statement", "justification", "products", "status", "vulnerability"]) and
    (.statements[0].vulnerability | keys == ["name"]) and
    .statements[0].vulnerability.name == "GO-2026-5932" and
    .statements[0].status == "not_affected" and
    .statements[0].justification == "vulnerable_code_not_present" and
    .statements[0].impact_statement == $impact and
    (.statements[0].products | type == "array" and length == 2) and
    all(.statements[0].products[];
      (keys == ["@id", "hashes", "subcomponents"]) and
      .["@id"] == $product and
      (.hashes | keys == ["sha-256"]) and
      (.subcomponents | type == "array" and length == 1) and
      (.subcomponents[0] | keys == ["@id"]) and
      .subcomponents[0]["@id"] == $subcomponent
    ) and
    ([.statements[0].products[].hashes["sha-256"]] | sort) ==
      ([$amd64_sha, $arm64_sha] | sort)
  ' "$vex_file" >/dev/null || die 'Gluetun OpenVEX scope or evidence differs from the reviewed contract'

go version -m "$binary" >"$tmpdir/buildinfo" 2>/dev/null ||
  die 'failed to read Go build metadata from Gluetun binary'
binary_go_version=$(LC_ALL=C sed -n '1s/^.*: //p' "$tmpdir/buildinfo")
[ "$binary_go_version" = go1.25.12 ] ||
  die 'Gluetun binary was not built with Go 1.25.12'

LC_ALL=C awk -F '\t' '
  $2 == "path" {
    count++
    if ($3 == "github.com/qdm12/gluetun/cmd/gluetun") valid++
  }
  END { exit(count == 1 && valid == 1 ? 0 : 1) }
' "$tmpdir/buildinfo" || die 'Gluetun binary main package identity differs'
LC_ALL=C awk -F '\t' '
  $2 == "mod" {
    count++
    if ($3 == "github.com/qdm12/gluetun" && $4 == "(devel)") valid++
  }
  END { exit(count == 1 && valid == 1 ? 0 : 1) }
' "$tmpdir/buildinfo" || die 'Gluetun binary root module identity differs'
LC_ALL=C awk -F '\t' '
  $2 == "dep" && $3 == "golang.org/x/crypto" {
    count++
    if ($4 == "v0.53.0" &&
        $5 == "h1:QZ4Muo8THX6CizN2vPPd5fBGHyogrdK9fG4wLPFUsto=") valid++
  }
  END { exit(count == 1 && valid == 1 ? 0 : 1) }
' "$tmpdir/buildinfo" || die 'Gluetun binary x/crypto module metadata differs'
LC_ALL=C awk -F '\t' '
  $2 == "dep" && $3 == "github.com/ProtonMail/go-crypto" {
    count++
    if ($4 == "v1.3.0-proton" &&
        $5 == "h1:tAQKQRZX/73VmzK6yHSCaRUOvS/3OYSQzhXQsrR7yUM=") valid++
  }
  END { exit(count == 1 && valid == 1 ? 0 : 1) }
' "$tmpdir/buildinfo" || die 'Gluetun binary ProtonMail crypto module metadata differs'

goos=$(read_build_setting GOOS) || die 'Gluetun binary GOOS metadata is missing or duplicated'
goarch=$(read_build_setting GOARCH) || die 'Gluetun binary GOARCH metadata is missing or duplicated'
cgo_enabled=$(read_build_setting CGO_ENABLED) || die 'Gluetun binary CGO metadata is missing or duplicated'
buildmode=$(read_build_setting -buildmode) || die 'Gluetun binary build mode metadata is missing or duplicated'
compiler=$(read_build_setting -compiler) || die 'Gluetun binary compiler metadata is missing or duplicated'
trimpath=$(read_build_setting -trimpath) || die 'Gluetun binary trimpath metadata is missing or duplicated'
[ "$goos" = linux ] && [ "$cgo_enabled" = 0 ] && [ "$buildmode" = exe ] &&
  [ "$compiler" = gc ] && [ "$trimpath" = true ] ||
  die 'Gluetun binary build settings differ from the reviewed recipe'

case $goarch in
  amd64)
    expected_binary_sha=$expected_amd64_sha
    [ "$(read_build_setting GOAMD64)" = v1 ] ||
      die 'Gluetun amd64 baseline differs from GOAMD64=v1'
    ;;
  arm64)
    expected_binary_sha=$expected_arm64_sha
    [ "$(read_build_setting GOARM64)" = v8.0 ] ||
      die 'Gluetun arm64 baseline differs from GOARM64=v8.0'
    ;;
  *) die "unsupported Gluetun binary architecture: $goarch" ;;
esac

actual_binary_sha=$(file_sha256 "$binary") || die 'failed to hash Gluetun binary'
[ "$actual_binary_sha" = "$expected_binary_sha" ] ||
  die "Gluetun $goarch binary hash differs from the reviewed build"
[ "$(jq --arg sha "$actual_binary_sha" \
  '[.statements[0].products[].hashes["sha-256"] | select(. == $sha)] | length' \
  "$vex_file")" -eq 1 ] || die 'Gluetun binary hash is not uniquely covered by OpenVEX'

# Binary-mode govulncheck v1.6.0 reports module/package metadata for the
# deprecated x/crypto package family because the separately maintained
# ProtonMail fork has matching symbol suffixes. It still exits zero because no
# affected symbol is reachable. Pin that informational shape and independently
# prove the exact compiled/source paths instead of discarding scanner output.
strings -a "$binary" >"$tmpdir/strings" || die 'failed to extract Gluetun binary strings'
vulnerable_string_status=0
LC_ALL=C grep -Fq 'golang.org/x/crypto/openpgp' "$tmpdir/strings" ||
  vulnerable_string_status=$?
case $vulnerable_string_status in
  0) die 'deprecated golang.org/x/crypto/openpgp code is present in Gluetun binary' ;;
  1) ;;
  *) die 'failed while checking Gluetun binary for deprecated OpenPGP code' ;;
esac
LC_ALL=C grep -Fq 'github.com/ProtonMail/go-crypto/openpgp' "$tmpdir/strings" ||
  die 'reviewed ProtonMail OpenPGP fork is not distinguishable in Gluetun binary'

govuln_status=0
govulncheck -json -mode=binary "$binary" >"$tmpdir/govuln.json" \
  2>"$tmpdir/govuln.stderr" || govuln_status=$?
[ "$govuln_status" -eq 0 ] ||
  die "govulncheck reported a reachable vulnerability or failed with status $govuln_status"
[ ! -s "$tmpdir/govuln.stderr" ] ||
  die 'govulncheck emitted unexpected stderr output'
jq -s -e '
  ([.[] | select(has("config")) | .config]) as $configs |
  ([.[] | select(has("SBOM")) | .SBOM]) as $sboms |
  ([.[] | select(has("finding")) | .finding]) as $findings |
  ($configs | length == 1) and
  $configs[0].scanner_name == "govulncheck" and
  $configs[0].scanner_version == "v1.6.0" and
  $configs[0].scan_level == "symbol" and
  $configs[0].scan_mode == "binary" and
  ($sboms | length == 1) and
  $sboms[0].go_version == "go1.25.12" and
  ([$sboms[0].modules[] |
    select(.path == "github.com/qdm12/gluetun" and .version == "(devel)")] | length == 1) and
  ([$sboms[0].modules[] | select(.path == "github.com/qdm12/gluetun")] | length == 1) and
  ([$sboms[0].modules[] |
    select(.path == "golang.org/x/crypto" and .version == "v0.53.0")] | length == 1) and
  ([$sboms[0].modules[] | select(.path == "golang.org/x/crypto")] | length == 1) and
  ([$sboms[0].modules[] |
    select(.path == "github.com/ProtonMail/go-crypto" and .version == "v1.3.0-proton")] |
    length == 1) and
  ([$sboms[0].modules[] | select(.path == "github.com/ProtonMail/go-crypto")] |
    length == 1) and
  ($findings | length == 15) and
  ([$findings[].osv] | unique == ["GO-2026-5932"]) and
  all($findings[];
    (keys == ["osv", "trace"]) and
    (.trace | type == "array" and length == 1) and
    .trace[0].module == "golang.org/x/crypto" and
    .trace[0].version == "v0.53.0" and
    ((.trace[0] | has("package") | not) or
      (.trace[0].package | test("^golang[.]org/x/crypto/openpgp(/|$)"))) and
    ((.trace[0] | keys) - ["function", "module", "package", "receiver", "version"] |
      length == 0)
  ) and
  ([$findings[].trace[0].package? // ""] | unique | sort) == [
    "golang.org/x/crypto/openpgp",
    "golang.org/x/crypto/openpgp/armor",
    "golang.org/x/crypto/openpgp/clearsign",
    "golang.org/x/crypto/openpgp/elgamal",
    "golang.org/x/crypto/openpgp/errors",
    "golang.org/x/crypto/openpgp/packet",
    "golang.org/x/crypto/openpgp/s2k"
  ] and
  ([$findings[].trace[0].function? // ""] | unique | sort) == [
    "org/x/crypto/openpgp/*",
    "org/x/crypto/openpgp/armor/*",
    "org/x/crypto/openpgp/clearsign/*",
    "org/x/crypto/openpgp/elgamal/*",
    "org/x/crypto/openpgp/errors/*",
    "org/x/crypto/openpgp/packet/*",
    "org/x/crypto/openpgp/s2k/*"
  ] and
  ([$findings[].trace[0].receiver? // ""] | unique | sort) == ["golang"]
' "$tmpdir/govuln.json" >/dev/null ||
  die 'govulncheck JSON is not the reviewed informational OpenPGP attribution'

[ "$(file_sha256 "$source_root/go.mod")" = "$expected_go_mod_sha" ] ||
  die 'Gluetun source go.mod differs from the binary build input'
[ "$(file_sha256 "$source_root/go.sum")" = "$expected_go_sum_sha" ] ||
  die 'Gluetun source go.sum differs from the binary build input'
source_toolchain=$(GOTOOLCHAIN=go1.25.12 GOENV=off go env GOVERSION) ||
  die 'Go 1.25.12 toolchain is unavailable for source audit'
[ "$source_toolchain" = go1.25.12 ] ||
  die 'source dependency audit did not select Go 1.25.12'
(
  CDPATH='' cd -- "$source_root"
  GOTOOLCHAIN=go1.25.12 GOENV=off GOWORK=off GOFLAGS=-mod=readonly \
    go mod verify >/dev/null
  GOTOOLCHAIN=go1.25.12 GOENV=off GOWORK=off \
    GOFLAGS='-mod=readonly -buildvcs=false' \
    go list -deps ./cmd/gluetun
) >"$tmpdir/source-deps" || die 'failed to reproduce Gluetun production dependency graph'

vulnerable_source_status=0
LC_ALL=C grep -Eq '^golang[.]org/x/crypto/openpgp(/|$)' "$tmpdir/source-deps" ||
  vulnerable_source_status=$?
case $vulnerable_source_status in
  0) die 'deprecated golang.org/x/crypto/openpgp code is present in source graph' ;;
  1) ;;
  *) die 'failed while checking Gluetun source dependency graph' ;;
esac
LC_ALL=C grep -Fxq 'github.com/ProtonMail/go-crypto/openpgp' "$tmpdir/source-deps" ||
  die 'maintained ProtonMail OpenPGP fork is absent from source graph'
source_crypto_module=$(
  CDPATH='' cd -- "$source_root"
  GOTOOLCHAIN=go1.25.12 GOENV=off GOWORK=off GOFLAGS=-mod=readonly \
    go list -m -f '{{.Path}} {{.Version}}' golang.org/x/crypto
) || die 'failed to resolve source x/crypto module'
[ "$source_crypto_module" = 'golang.org/x/crypto v0.53.0' ] ||
  die 'source x/crypto module differs from reviewed VEX subcomponent'

printf 'Gluetun GO-2026-5932 audit passed: %s (%s)\n' \
  "$actual_binary_sha" "$goarch"
