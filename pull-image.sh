#!/usr/bin/env bash
#
# pull-image.sh — refresh the images behind the Docker Compose stacks defined in
# this repository, then report what changed and which containers still need a
# redeploy to start using the new image.
#
# A Compose container counts as ours when one of its Compose files lives under
# ROOT (default: the directory holding this script), or when its Compose file
# path ends in a path that exists under ROOT. The second rule is how git-backed
# stacks deployed by Portainer or Komodo show up, e.g.
#   /data/compose/288/ChatStack/docker-compose.yml  ~  ROOT/ChatStack/docker-compose.yml
#
# Design notes
#   * errexit is deliberately off. Background workers, `read -t` timeouts and
#     arithmetic make `set -e` semantics a source of surprises, so every
#     fallible command is checked explicitly instead.
#   * Helpers hand results back through REPLY (or documented globals) rather
#     than $(...), so hot paths such as the TUI renderer never fork.
#   * Each pull runs in a background worker that logs to its own file and
#     reports back through a small result file. Only this process writes to
#     the terminal, so parallel pulls can't garble it.
#
# Tests: tests/pull-image.bats (bats-core, driven by a fake docker CLI).

set -uo pipefail

if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1))); then
  printf 'pull-image.sh: bash 5.1 or newer is required (found %s)\n' "$BASH_VERSION" >&2
  exit 3
fi

# ─── Constants ───────────────────────────────────────────────────────────────

readonly VERSION='2.0.0'
readonly PROG='pull-image.sh'
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 3
readonly SCRIPT_DIR

readonly LABEL_PROJECT='com.docker.compose.project'
readonly LABEL_SERVICE='com.docker.compose.service'
readonly LABEL_WORKDIR='com.docker.compose.project.working_dir'
readonly LABEL_CONFIGS='com.docker.compose.project.config_files'
readonly SEP=$'\x1f' # field separator for `docker --format` output

readonly EXIT_OK=0 EXIT_FAILED=1 EXIT_USAGE=2 EXIT_ENV=3 EXIT_INTERRUPTED=130

# ─── Options (flags override the PULL_IMAGE_* environment defaults) ──────────

OPT_ROOT=${PULL_IMAGE_ROOT:-$SCRIPT_DIR}
OPT_JOBS=${PULL_IMAGE_JOBS:-16}
OPT_RETRIES=${PULL_IMAGE_RETRIES:-2}
OPT_TIMEOUT=${PULL_IMAGE_TIMEOUT:-1800}
OPT_MIN_FREE_GB=${PULL_IMAGE_MIN_FREE_GB:-5}
OPT_LOG_DIR=${PULL_IMAGE_LOG_DIR:-}
OPT_IGNORE_FILE=''
OPT_USE_IGNORE_FILE=1
OPT_DRY_RUN=0
OPT_TUI=0
OPT_JSON=0
OPT_QUIET=0
OPT_VERBOSE=0
OPT_COLOR=auto
OPT_ALL_PROJECTS=0
OPT_INCLUDE_STOPPED=0
OPT_PULL_LOCAL=0
OPT_INCLUDE=()
OPT_EXCLUDE=()
OPT_PROJECTS=()
OPT_SKIP_PROJECTS=()

# Internal knobs, mostly for tests.
LOCK_PATH=${PULL_IMAGE_LOCK:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/pull-image.lock}
BACKOFF_UNIT_MS=${PULL_IMAGE_BACKOFF_MS:-1000}
read -ra DOCKER <<<"${DOCKER_BIN:-docker}" # may be a wrapper, e.g. "sudo docker"

# ─── Run state ───────────────────────────────────────────────────────────────

declare -A COMPOSE_SUFFIX=() # path suffix (>= 2 parts) of a local Compose file -> ROOT-relative path
COMPOSE_FILE_COUNT=0
declare -A LOCAL_ID=()          # canonical image ref -> local image ID
declare -A REGISTRY_ID=()       # image IDs with a registry digest (pulled, not built here)
declare -A IGNORED_PROJECTS=()  # project -> containers not defined under ROOT
declare -A FILTERED_PROJECTS=() # project -> containers left out by project filters

# Containers, by index.
CTR_NAME=() CTR_PROJECT=() CTR_SERVICE=() CTR_RUN_ID=() CTR_KEY=() CTR_IMG=()
CTR_CONFIGS=() CTR_WORKDIR=() CTR_MATCH=()

# Images, by index, sorted by reference. IMG_KEY holds the canonical reference.
IMG_REF=() IMG_KEY=() IMG_PROJECTS=() IMG_CTRS=() IMG_KIND=() IMG_LOCAL_ID=() IMG_NEW_ID=()
IMG_STATE=() IMG_NOTE=() IMG_ATTEMPTS=() IMG_MS=() IMG_START_MS=() IMG_LOG=() IMG_SEL=() IMG_STALE=()
declare -A IMG_INDEX=() # canonical ref -> image index
STALE_CTRS=()           # containers running an older image than their tag now points to

declare -A RUNNING=() # worker pid -> image index
PULL_CMD=()
WORK_DIR='' LOG_DIR='' KEEP_LOGS=0 LOCK_FD=''
DOCKER_ROOT_DIR=''
INTERRUPTIBLE=0 ABORT_REQUESTED=0 ABORT_SIGNAL=''
RUN_START_MS=0 RUN_ELAPSED_MS=0 # RUN_START_MS: start of the current pass
PROGRESS_DONE=0 PROGRESS_TOTAL=0 PROGRESS_REF_W=0
FAIL_CLASS='' FAIL_MSG=''
WARNINGS=()
REPORT_TEXT=() REPORT_STYLE=()

# Presentation; setup_output fills these in.
C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_INV=''
declare -A STYLE=() ICON=()
declare -A STATE_STYLE=([queued]=dim [pulling]=info [updated]=ok [unchanged]=dim [failed]=err
  [skipped]=dim [excluded]=dim [cancelled]=warn)
SPINNER=('|' '/' '-' "\\")
GLYPH_ELLIPSIS='~' GLYPH_FULL='#' GLYPH_EMPTY='-' GLYPH_ARROW='->' GLYPH_POINTER='>' GLYPH_SEP='-'

# ─── Usage and arguments ─────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $PROG [options]

Pull the images used by Docker Compose containers whose Compose definition
lives under ROOT (default: $SCRIPT_DIR), then report which images
changed and which containers still run an outdated image.

Modes:
  (default)                pull, printing one line per image as it finishes
  -T, --tui                interactive UI: choose images, watch live progress
  -n, --dry-run            show the plan and outdated containers; pull nothing
      --json               write a machine-readable report to stdout

Choosing images:
  -i, --include GLOB       only images matching GLOB (repeatable)
  -x, --exclude GLOB       skip images matching GLOB (repeatable)
  -p, --project GLOB       only Compose projects matching GLOB (repeatable)
  -P, --skip-project GLOB  skip Compose projects matching GLOB (repeatable)
  -A, --all-projects       every Compose container, defined under ROOT or not
  -a, --include-stopped    consider stopped containers too
      --pull-local         also try locally built images (no registry digest)
      --ignore-file FILE   extra exclusions (default: ROOT/.pull-image-ignore)
      --no-ignore-file     do not read an ignore file
  -r, --root DIR           directory holding the Compose definitions

Pulling:
  -j, --jobs N             parallel pulls, 1-64 (default: $OPT_JOBS)
      --retries N          retries after a transient failure (default: $OPT_RETRIES)
      --timeout SECONDS    limit per attempt, 0 for none (default: $OPT_TIMEOUT)
      --log-dir DIR        keep per-image logs under DIR (default: a temporary
                           directory, kept only when a pull fails)
      --min-free GB        warn below this much free space for Docker (default: $OPT_MIN_FREE_GB)

Output:
  -q, --quiet              print failures and the summary only
  -v, --verbose            also list excluded images and failure log tails
      --color WHEN         auto, always or never (NO_COLOR is honoured)
  -h, --help               show this help
  -V, --version            show the version

A GLOB matches an image reference as written in the Compose file, in its short
form (redis:latest) or fully qualified (docker.io/library/redis:latest). Outdated
containers are reported for the images not excluded. The ignore file holds
one GLOB per line; prefix a line with "project:" to skip a whole Compose
project; "#" starts a comment.

Environment: PULL_IMAGE_JOBS, PULL_IMAGE_RETRIES, PULL_IMAGE_TIMEOUT,
PULL_IMAGE_ROOT, PULL_IMAGE_LOG_DIR and PULL_IMAGE_MIN_FREE_GB set defaults.
DOCKER_BIN replaces the docker command (e.g. "sudo docker").

Exit status: 0 success, 1 at least one pull failed, 2 usage error,
3 environment problem (Docker unreachable, another run active), 130 interrupted.
EOF
}

usage_error() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  printf "Try '%s --help' for more information.\n" "$PROG" >&2
  exit "$EXIT_USAGE"
}

need_value() {
  if (($# < 2)); then usage_error "option $1 needs a value"; fi
}

# check_uint NAME VALUE MIN MAX -> REPLY: VALUE as a decimal integer.
check_uint() {
  if [[ ! $2 =~ ^[0-9]{1,9}$ ]] || ((10#$2 < $3 || 10#$2 > $4)); then
    usage_error "$1 must be an integer from $3 to $4 (got '$2')"
  fi
  REPLY=$((10#$2))
}

parse_args() {
  while (($# > 0)); do
    case $1 in
    --*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}" ;;
    -[ixpPrj]?*) set -- "${1:0:2}" "${1:2}" "${@:2}" ;;
    esac
    case $1 in
    -h | --help)
      usage
      exit "$EXIT_OK"
      ;;
    -V | --version)
      printf '%s %s\n' "$PROG" "$VERSION"
      exit "$EXIT_OK"
      ;;
    -n | --dry-run) OPT_DRY_RUN=1 ;;
    -T | --tui) OPT_TUI=1 ;;
    --json) OPT_JSON=1 ;;
    -q | --quiet) OPT_QUIET=1 ;;
    -v | --verbose) OPT_VERBOSE=1 ;;
    -A | --all-projects) OPT_ALL_PROJECTS=1 ;;
    -a | --include-stopped) OPT_INCLUDE_STOPPED=1 ;;
    --pull-local) OPT_PULL_LOCAL=1 ;;
    --no-ignore-file) OPT_USE_IGNORE_FILE=0 ;;
    -i | --include | -x | --exclude | -p | --project | -P | --skip-project | -r | --root | \
      -j | --jobs | --retries | --timeout | --log-dir | --min-free | --color | --ignore-file)
      need_value "$@"
      case $1 in
      -i | --include) OPT_INCLUDE+=("$2") ;;
      -x | --exclude) OPT_EXCLUDE+=("$2") ;;
      -p | --project) OPT_PROJECTS+=("$2") ;;
      -P | --skip-project) OPT_SKIP_PROJECTS+=("$2") ;;
      -r | --root) OPT_ROOT=$2 ;;
      -j | --jobs) OPT_JOBS=$2 ;;
      --retries) OPT_RETRIES=$2 ;;
      --timeout) OPT_TIMEOUT=$2 ;;
      --log-dir) OPT_LOG_DIR=$2 ;;
      --min-free) OPT_MIN_FREE_GB=$2 ;;
      --color) OPT_COLOR=$2 ;;
      --ignore-file) OPT_IGNORE_FILE=$2 ;;
      esac
      shift
      ;;
    --)
      shift
      break
      ;;
    -*) usage_error "unknown option: $1" ;;
    *) usage_error "unexpected argument: $1" ;;
    esac
    shift
  done
  if (($# > 0)); then usage_error "unexpected argument: $1"; fi
  validate_args
}

validate_args() {
  check_uint --jobs "$OPT_JOBS" 1 64 && OPT_JOBS=$REPLY
  check_uint --retries "$OPT_RETRIES" 0 10 && OPT_RETRIES=$REPLY
  check_uint --timeout "$OPT_TIMEOUT" 0 86400 && OPT_TIMEOUT=$REPLY
  check_uint --min-free "$OPT_MIN_FREE_GB" 0 100000 && OPT_MIN_FREE_GB=$REPLY
  case $OPT_COLOR in
  auto | always | never) ;;
  *) usage_error "--color must be auto, always or never (got '$OPT_COLOR')" ;;
  esac
  if [[ ! -d $OPT_ROOT ]]; then usage_error "--root is not a directory: $OPT_ROOT"; fi
  OPT_ROOT=$(CDPATH='' cd -- "$OPT_ROOT" && pwd -P) || usage_error "cannot resolve --root: $OPT_ROOT"
  if [[ -n $OPT_IGNORE_FILE && ! -r $OPT_IGNORE_FILE ]]; then
    usage_error "cannot read ignore file: $OPT_IGNORE_FILE"
  fi
  if ((OPT_TUI)); then
    if ((OPT_JSON)); then usage_error '--tui and --json cannot be combined'; fi
    if [[ ! -t 0 || ! -t 1 ]]; then usage_error '--tui needs an interactive terminal'; fi
  fi
}

# ─── Output ──────────────────────────────────────────────────────────────────

is_utf8_locale() {
  local locale=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
  [[ ${locale^^} == *UTF-8* || ${locale^^} == *UTF8* ]]
}

setup_output() {
  # Human-readable output goes to fd 3; with --json, stdout carries only JSON.
  if ((OPT_JSON)); then exec 3>&2; else exec 3>&1; fi

  local color=0
  case $OPT_COLOR in
  always) color=1 ;;
  auto)
    if [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]] && { ((OPT_TUI)) || [[ -t 3 ]]; }; then
      color=1
    fi
    ;;
  esac
  if ((color)); then
    C_DIM=$'\e[2m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_CYAN=$'\e[36m'
  fi
  # Bold and reverse video aren't colours; the TUI needs them regardless.
  if ((color || OPT_TUI)); then
    C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_INV=$'\e[7m'
  fi
  STYLE=([plain]='' [title]=$C_BOLD [head]=$C_BOLD$C_CYAN [dim]=$C_DIM [ok]=$C_GREEN
    [warn]=$C_YELLOW [err]=$C_RED [info]=$C_CYAN [bar]=$C_INV$C_BOLD [cursor]=$C_INV)

  if is_utf8_locale; then
    ICON=([queued]='·' [pulling]='⠿' [updated]='↑' [unchanged]='✓' [failed]='✗' [skipped]='−'
      [excluded]='−' [cancelled]='⊘' [retry]='⟳' [hint]='↳')
    SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    GLYPH_ELLIPSIS='…' GLYPH_FULL='█' GLYPH_EMPTY='░' GLYPH_ARROW='→' GLYPH_POINTER='▸' GLYPH_SEP='·'
  else
    ICON=([queued]='.' [pulling]='*' [updated]='+' [unchanged]='=' [failed]='x' [skipped]='-'
      [excluded]='-' [cancelled]='/' [retry]='r' [hint]='>')
  fi
}

info() {
  if ((!OPT_QUIET)); then printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&3; fi
}

say() { printf '%s\n' "$*" >&3; }

warn() {
  if ((TUI_ACTIVE)); then
    WARNINGS+=("$*")
  else
    printf '%swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
  fi
}

die() {
  local code=$1
  shift
  tui_leave
  printf '%s%s: %s%s\n' "$C_RED" "$PROG" "$*" "$C_RESET" >&2
  exit "$code"
}

# ─── Pure helpers ────────────────────────────────────────────────────────────

now_ms() {
  local us=${EPOCHREALTIME//[!0-9]/}
  REPLY=$((10#$us / 1000))
}

# fmt_duration MS -> REPLY, e.g. 0.8s, 12.4s, 3m07s, 1h02m.
fmt_duration() {
  local ms=$1
  if ((ms < 60000)); then
    printf -v REPLY '%d.%ds' $((ms / 1000)) $((ms % 1000 / 100))
  elif ((ms < 3600000)); then
    printf -v REPLY '%dm%02ds' $((ms / 60000)) $((ms % 60000 / 1000))
  else
    printf -v REPLY '%dh%02dm' $((ms / 3600000)) $((ms % 3600000 / 60000))
  fi
}

# fmt_clock MS -> REPLY as m:ss.
fmt_clock() {
  printf -v REPLY '%d:%02d' $(($1 / 60000)) $(($1 / 1000 % 60))
}

short_id() {
  REPLY=${1#sha256:}
  REPLY=${REPLY:0:12}
}

# match_any VALUE GLOB... succeeds when VALUE matches a GLOB; REPLY = that GLOB.
match_any() {
  local value=$1 pattern
  shift
  for pattern in "$@"; do
    # shellcheck disable=SC2053 # unquoted right-hand side: glob matching is the point
    if [[ $value == $pattern ]]; then
      REPLY=$pattern
      return 0
    fi
  done
  return 1
}

# normalize_ref REF -> REPLY: the fully qualified reference Docker resolves REF
# to, so "redis", "redis:latest" and "docker.io/library/redis:latest" are one
# image. A digest pins the content, so the tag is dropped when one is present.
normalize_ref() {
  local name=$1 digest='' tag='' domain path
  if [[ $name == *@* ]]; then
    digest=${name#*@}
    name=${name%%@*}
  fi
  if [[ ${name##*/} == *:* ]]; then
    tag=${name##*:}
    name=${name%:*}
  fi
  domain=${name%%/*}
  if [[ $name == */* && ($domain == *.* || $domain == *:* || $domain == localhost) ]]; then
    path=${name#*/}
  else
    domain=docker.io
    path=$name
  fi
  if [[ $domain == index.docker.io ]]; then domain=docker.io; fi
  if [[ $domain == docker.io && $path != */* ]]; then path=library/$path; fi
  if [[ -n $digest ]]; then
    REPLY=$domain/$path@$digest
  else
    REPLY=$domain/$path:${tag:-latest}
  fi
}

# familiar_ref CANONICAL -> REPLY: the short form people usually write,
# e.g. docker.io/library/redis:latest -> redis:latest.
familiar_ref() {
  REPLY=${1#docker.io/}
  REPLY=${REPLY#library/}
}

# image_matches IMAGE GLOB... succeeds when a GLOB matches the image as written,
# in its short form or fully qualified; REPLY = the matching GLOB.
image_matches() {
  local i=$1
  shift
  match_any "${IMG_REF[i]}" "$@" && return 0
  match_any "${IMG_KEY[i]}" "$@" && return 0
  familiar_ref "${IMG_KEY[i]}"
  match_any "$REPLY" "$@"
}

# sort_words WORD... -> REPLY: the words in ascending order, space-separated.
sort_words() {
  local -a sorted=()
  local word j
  for word in "$@"; do
    j=${#sorted[@]}
    while ((j > 0)) && [[ ${sorted[j - 1]} > $word ]]; do
      sorted[j]=${sorted[j - 1]}
      j=$((j - 1))
    done
    sorted[j]=$word
  done
  REPLY=${sorted[*]}
}

# fit TEXT WIDTH -> REPLY: TEXT cut with an ellipsis, or space-padded, to WIDTH.
fit() {
  local s=$1 w=$2
  if ((w <= 0)); then
    REPLY=''
    return 0
  fi
  if ((${#s} > w)); then s=${s:0:w-1}$GLYPH_ELLIPSIS; fi
  printf -v REPLY '%s%*s' "$s" $((w - ${#s})) ''
}

# fit_mid TEXT WIDTH -> REPLY: like fit, but cuts the middle so the end of the
# text (an image tag, say) stays visible.
fit_mid() {
  local s=$1 w=$2 n=${#1} tail
  if ((n > w && w >= 8)); then
    tail=$(((w - 1) * 3 / 5))
    s=${s:0:w-1-tail}$GLYPH_ELLIPSIS${s:n-tail}
  fi
  fit "$s" "$w"
}

# json_str VALUE -> REPLY: VALUE as a quoted JSON string.
json_str() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=${s//[$'\x01'-$'\x1f']/}
  REPLY="\"$s\""
}

# json_list VALUE... -> REPLY: a JSON array of strings.
json_list() {
  local joined='' value
  for value in "$@"; do
    json_str "$value"
    joined+=${joined:+,}$REPLY
  done
  REPLY="[$joined]"
}

json_seconds() {
  printf -v REPLY '%d.%03d' $(($1 / 1000)) $(($1 % 1000))
}

# classify_pull_failure EXIT_CODE LOG -> FAIL_CLASS, FAIL_MSG.
# FAIL_CLASS is permanent (retrying won't help), ratelimit, or transient.
classify_pull_failure() {
  local rc=$1 log=$2 line='' text='' msg=''
  if [[ -r $log ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ -z ${line//[[:space:]]/} ]]; then continue; fi
      text+=$line$'\n'
      if [[ $line == *[Ee]rror* ]]; then msg=$line; fi
    done <"$log"
  fi
  if [[ -z $msg ]]; then
    msg=${text%$'\n'}
    msg=${msg##*$'\n'}
  fi
  msg=${msg#Error response from daemon: }
  msg=${msg#Error: }

  FAIL_CLASS=transient
  if ((rc == 124 || rc == 137)); then
    FAIL_MSG="timed out after ${OPT_TIMEOUT}s"
    return 0
  fi
  case ${text,,} in
  *toomanyrequests* | *"rate limit"*) FAIL_CLASS=ratelimit ;;
  *"pull access denied"* | *"repository does not exist"* | *"requested access to the resource is denied"* | \
    *unauthorized* | *"authentication required"* | *"manifest unknown"* | *": not found"* | \
    *"no matching manifest"* | *"invalid reference format"*)
    FAIL_CLASS=permanent
    ;;
  esac
  if ((rc == 126 || rc == 127)); then FAIL_CLASS=permanent; fi
  FAIL_MSG=${msg:-"docker pull exited with status $rc"}
  if ((${#FAIL_MSG} > 300)); then FAIL_MSG=${FAIL_MSG:0:299}$GLYPH_ELLIPSIS; fi
}

# backoff_ms ATTEMPT CLASS -> REPLY: capped exponential backoff with jitter.
backoff_ms() {
  local units
  if [[ $2 == ratelimit ]]; then units=$((15 * $1)); else units=$((1 << $1)); fi
  if ((units > 60)); then units=60; fi
  REPLY=$((units * BACKOFF_UNIT_MS + RANDOM % (BACKOFF_UNIT_MS + 1)))
}

# ─── Preflight ───────────────────────────────────────────────────────────────

preflight() {
  local answer='' line
  local -a guard=()
  if ! command -v "${DOCKER[0]}" >/dev/null 2>&1; then
    die "$EXIT_ENV" "docker CLI not found: ${DOCKER[0]}"
  fi
  if command -v timeout >/dev/null 2>&1; then
    guard=(timeout 30) # a wedged daemon must not hang the script forever
  elif ((OPT_TIMEOUT > 0)); then
    warn 'timeout(1) is not installed; pulls will run without a time limit'
    OPT_TIMEOUT=0
  fi
  if ! answer=$("${guard[@]}" "${DOCKER[@]}" info --format "{{.ServerVersion}}$SEP{{.DockerRootDir}}" 2>&1); then
    answer=${answer##*$'\n'}
    die "$EXIT_ENV" "cannot talk to the Docker daemon: ${answer:-no answer within 30s}"
  fi
  while IFS= read -r line; do
    if [[ $line == *"$SEP"* ]]; then DOCKER_ROOT_DIR=${line#*"$SEP"}; fi
  done <<<"$answer"

  if ((OPT_TIMEOUT > 0)); then
    PULL_CMD=(timeout --kill-after=15 "$OPT_TIMEOUT" "${DOCKER[@]}" pull)
  else
    PULL_CMD=("${DOCKER[@]}" pull)
  fi
}

load_ignore_file() {
  local file=$OPT_IGNORE_FILE line
  if ((!OPT_USE_IGNORE_FILE)); then return 0; fi
  if [[ -z $file ]]; then
    file=$OPT_ROOT/.pull-image-ignore
    if [[ ! -f $file ]]; then return 0; fi
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    if [[ -z $line ]]; then continue; fi
    if [[ $line == project:* ]]; then
      OPT_SKIP_PROJECTS+=("${line#project:}")
    else
      OPT_EXCLUDE+=("$line")
    fi
  done <"$file"
}

acquire_lock() {
  if ! command -v flock >/dev/null 2>&1; then
    warn 'flock(1) is not installed; concurrent runs are not prevented'
    return 0
  fi
  if ! exec {LOCK_FD}>>"$LOCK_PATH"; then
    die "$EXIT_ENV" "cannot open lock file: $LOCK_PATH"
  fi
  if ! flock -n "$LOCK_FD"; then
    die "$EXIT_ENV" "another $PROG run is in progress (lock: $LOCK_PATH)"
  fi
}

check_disk_space() {
  local avail='' _
  if ((OPT_MIN_FREE_GB == 0)) || [[ -z $DOCKER_ROOT_DIR || ! -d $DOCKER_ROOT_DIR ]]; then return 0; fi
  if [[ -n ${DOCKER_HOST:-} && $DOCKER_HOST != unix://* ]]; then return 0; fi # remote daemon
  { read -r _ && read -r _ _ _ avail _; } < <(df -Pk -- "$DOCKER_ROOT_DIR" 2>/dev/null)
  if [[ $avail =~ ^[0-9]+$ ]] && ((avail < OPT_MIN_FREE_GB * 1024 * 1024)); then
    warn "only $((avail / 1024 / 1024)) GiB free under $DOCKER_ROOT_DIR (threshold: $OPT_MIN_FREE_GB GiB)"
  fi
}

prepare_workdir() {
  local i
  WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pull-image.XXXXXX") || die "$EXIT_ENV" 'cannot create a temporary directory'
  if [[ -n $OPT_LOG_DIR ]]; then
    printf -v LOG_DIR '%s/%(%Y%m%d-%H%M%S)T' "$OPT_LOG_DIR" -1
    KEEP_LOGS=1
  else
    LOG_DIR=$WORK_DIR/logs
  fi
  mkdir -p -- "$LOG_DIR" || die "$EXIT_ENV" "cannot create log directory: $LOG_DIR"
  for i in "${!IMG_REF[@]}"; do
    printf -v 'IMG_LOG[i]' '%s/%03d-%s.log' "$LOG_DIR" "$i" "${IMG_REF[i]//[^A-Za-z0-9._-]/_}"
  done
}

# ─── Discovery ───────────────────────────────────────────────────────────────

# Indexes every Compose file under ROOT by each of its path suffixes with at
# least two parts, so a.yml at ROOT/x/stack/a.yml is found as "x/stack/a.yml"
# and "stack/a.yml". Where suffixes collide, the file nearest ROOT wins.
index_compose_files() {
  local path rel suffix
  while IFS= read -r -d '' path; do
    rel=${path#"$OPT_ROOT"/}
    COMPOSE_FILE_COUNT=$((COMPOSE_FILE_COUNT + 1))
    suffix=$rel
    while [[ $suffix == */* ]]; do
      if [[ -z ${COMPOSE_SUFFIX[$suffix]:-} ]] || ((${#rel} < ${#COMPOSE_SUFFIX[$suffix]})); then
        COMPOSE_SUFFIX[$suffix]=$rel
      fi
      suffix=${suffix#*/}
    done
  done < <(find "$OPT_ROOT" \( -name .git -o -name node_modules \) -prune -o -type f \
    \( -name 'compose.y*ml' -o -name 'compose.*.y*ml' -o -name 'docker-compose.y*ml' \
    -o -name 'docker-compose.*.y*ml' \) -print0 2>/dev/null)
}

# match_compose_path PATH -> REPLY: the ROOT-relative Compose file PATH refers
# to, matching the longest path suffix first.
match_compose_path() {
  local path=$1 suffix
  if [[ $path == "$OPT_ROOT"/* && -f $path ]]; then
    REPLY=${path#"$OPT_ROOT"/}
    return 0
  fi
  suffix=${path#/}
  while [[ $suffix == */* ]]; do
    if [[ -n ${COMPOSE_SUFFIX[$suffix]:-} ]]; then
      REPLY=${COMPOSE_SUFFIX[$suffix]}
      return 0
    fi
    suffix=${suffix#*/}
  done
  return 1
}

# match_container WORKING_DIR CONFIG_FILES -> REPLY: the local Compose file
# behind a container, from its comma-separated config_files label.
match_container() {
  local workdir=$1 file
  local -a files=()
  IFS=, read -ra files <<<"$2"
  for file in "${files[@]}"; do
    if match_compose_path "$file"; then return 0; fi
    if [[ -n $workdir && $file != "$workdir"/* ]] && match_compose_path "$workdir/${file##*/}"; then
      return 0
    fi
  done
  return 1
}

project_selected() {
  if ((${#OPT_PROJECTS[@]})) && ! match_any "$1" "${OPT_PROJECTS[@]}"; then return 1; fi
  if ((${#OPT_SKIP_PROJECTS[@]})) && match_any "$1" "${OPT_SKIP_PROJECTS[@]}"; then return 1; fi
  return 0
}

# Maps canonical references to local image IDs. --all matters: an image pulled
# by digest has no tag and is otherwise hidden.
index_local_images() {
  local repo tag digest id
  while IFS=$SEP read -r repo tag digest id; do
    if [[ -z $id || $repo == '<none>' ]]; then continue; fi
    if [[ $tag != '<none>' ]]; then
      normalize_ref "$repo:$tag"
      LOCAL_ID[$REPLY]=$id
    fi
    if [[ $digest == sha256:* ]]; then
      normalize_ref "$repo@$digest"
      LOCAL_ID[$REPLY]=$id
      REGISTRY_ID[$id]=1
    fi
  done < <("${DOCKER[@]}" image ls --all --no-trunc --digests \
    --format "{{.Repository}}$SEP{{.Tag}}$SEP{{.Digest}}$SEP{{.ID}}" 2>/dev/null)
}

# Collects the Compose containers we manage. Fills CTR_* plus the per-image
# scratch maps image_ref/image_projects (canonical ref -> value), which the
# caller declares.
discover_containers() {
  local out name ref run_id project service workdir configs match c key
  local -a ids=() ps_args=(ps --quiet --no-trunc --filter "label=$LABEL_PROJECT")
  if ((OPT_INCLUDE_STOPPED)); then ps_args+=(--all); fi
  if ! out=$("${DOCKER[@]}" "${ps_args[@]}" 2>&1); then
    die "$EXIT_ENV" "docker ps failed: ${out##*$'\n'}"
  fi
  if [[ -z $out ]]; then return 0; fi
  mapfile -t ids <<<"$out"

  local fmt="{{.Name}}$SEP{{.Config.Image}}$SEP{{.Image}}"
  fmt+="$SEP{{index .Config.Labels \"$LABEL_PROJECT\"}}$SEP{{index .Config.Labels \"$LABEL_SERVICE\"}}"
  fmt+="$SEP{{index .Config.Labels \"$LABEL_WORKDIR\"}}$SEP{{index .Config.Labels \"$LABEL_CONFIGS\"}}"
  # Containers that vanish between `ps` and `inspect` are simply skipped.
  while IFS=$SEP read -r name ref run_id project service workdir configs; do
    if [[ -z $name || -z $ref ]]; then continue; fi
    name=${name#/}
    project=${project:-unknown}
    match=''
    if ((!OPT_ALL_PROJECTS)); then
      if ! match_container "$workdir" "$configs"; then
        IGNORED_PROJECTS[$project]=$((${IGNORED_PROJECTS[$project]:-0} + 1))
        continue
      fi
      match=$REPLY
    fi
    if ! project_selected "$project"; then
      FILTERED_PROJECTS[$project]=$((${FILTERED_PROJECTS[$project]:-0} + 1))
      continue
    fi

    normalize_ref "$ref"
    key=$REPLY
    c=${#CTR_NAME[@]}
    CTR_NAME[c]=$name CTR_PROJECT[c]=$project CTR_SERVICE[c]=$service CTR_RUN_ID[c]=$run_id
    CTR_KEY[c]=$key CTR_CONFIGS[c]=$configs CTR_WORKDIR[c]=$workdir CTR_MATCH[c]=$match
    # Keep the shortest spelling of a reference: it is the one people write.
    if [[ -z ${image_ref[$key]:-} ]] || ((${#ref} < ${#image_ref[$key]})); then
      image_ref[$key]=$ref
    fi
    if [[ " ${image_projects[$key]:-} " != *" $project "* ]]; then
      image_projects[$key]+=${image_projects[$key]:+ }$project
    fi
  done < <("${DOCKER[@]}" inspect --type container --format "$fmt" "${ids[@]}" 2>/dev/null)
}

discover() {
  local -A image_ref=() image_projects=()
  local line key i c
  local -a sorted=() words=()
  index_compose_files
  index_local_images
  discover_containers
  if ((${#image_ref[@]} == 0)); then return 0; fi

  mapfile -t sorted < <(for key in "${!image_ref[@]}"; do
    printf '%s%s%s\n' "${image_ref[$key]}" "$SEP" "$key"
  done | LC_ALL=C sort)
  for line in "${sorted[@]}"; do
    i=${#IMG_REF[@]}
    key=${line#*"$SEP"}
    IMG_REF[i]=${line%%"$SEP"*}
    IMG_KEY[i]=$key
    IMG_INDEX[$key]=$i
    read -ra words <<<"${image_projects[$key]}"
    sort_words "${words[@]}"
    IMG_PROJECTS[i]=$REPLY
    IMG_LOCAL_ID[i]=${LOCAL_ID[$key]:-}
    IMG_CTRS[i]='' IMG_KIND[i]='' IMG_NEW_ID[i]='' IMG_STATE[i]=queued IMG_NOTE[i]=''
    IMG_ATTEMPTS[i]=0 IMG_MS[i]=0 IMG_START_MS[i]=0 IMG_LOG[i]='' IMG_SEL[i]=0 IMG_STALE[i]=0
  done
  for c in "${!CTR_NAME[@]}"; do
    i=${IMG_INDEX[${CTR_KEY[c]}]}
    CTR_IMG[c]=$i
    IMG_CTRS[i]+=${IMG_CTRS[i]:+ }$c
  done
}

# ─── Planning ────────────────────────────────────────────────────────────────

set_state() {
  IMG_STATE[$1]=$2
  IMG_NOTE[$1]=$3
}

plan_images() {
  local i ref key id
  for i in "${!IMG_REF[@]}"; do
    ref=${IMG_REF[i]} key=${IMG_KEY[i]} id=${IMG_LOCAL_ID[i]}
    if [[ $ref == sha256:* || $ref =~ ^[0-9a-f]{12,64}$ ]]; then
      IMG_KIND[i]=id
    elif [[ $key == *@* ]]; then
      IMG_KIND[i]=pinned
    elif [[ -n $id && -z ${REGISTRY_ID[$id]:-} ]]; then
      IMG_KIND[i]=local
    fi

    if ((${#OPT_INCLUDE[@]})) && ! image_matches "$i" "${OPT_INCLUDE[@]}"; then
      set_state "$i" excluded 'not matched by --include'
    elif ((${#OPT_EXCLUDE[@]})) && image_matches "$i" "${OPT_EXCLUDE[@]}"; then
      set_state "$i" excluded "matches exclusion '$REPLY'"
    elif [[ ${IMG_KIND[i]} == id ]]; then
      set_state "$i" skipped 'container was created from an image ID'
    elif [[ ${IMG_KIND[i]} == pinned && -n $id ]]; then
      set_state "$i" skipped 'pinned by digest and already present'
    elif [[ ${IMG_KIND[i]} == local ]] && ((!OPT_PULL_LOCAL)); then
      set_state "$i" skipped 'built locally (no registry digest); see --pull-local'
    fi
  done
}

# Finds containers whose running image differs from what their reference now
# points to locally, i.e. a newer image was pulled but never deployed. Images
# excluded by filters are left out, so the report follows the selection.
compute_stale() {
  local c i current
  STALE_CTRS=()
  for i in "${!IMG_REF[@]}"; do IMG_STALE[i]=0; done
  for c in "${!CTR_NAME[@]}"; do
    i=${CTR_IMG[c]}
    if [[ ${IMG_STATE[i]} == excluded ]]; then continue; fi
    current=${IMG_NEW_ID[i]:-${IMG_LOCAL_ID[i]}}
    if [[ -n $current && -n ${CTR_RUN_ID[c]} && $current != "${CTR_RUN_ID[c]}" ]]; then
      STALE_CTRS+=("$c")
      IMG_STALE[i]=$((IMG_STALE[i] + 1))
    fi
  done
}

count_state() {
  local state i
  REPLY=0
  for i in "${!IMG_STATE[@]}"; do
    for state in "$@"; do
      if [[ ${IMG_STATE[i]} == "$state" ]]; then REPLY=$((REPLY + 1)); fi
    done
  done
}

# ─── Pull workers ────────────────────────────────────────────────────────────

# write_status IMAGE FIELD... : the worker's live state, read by the TUI.
write_status() {
  local file=$WORK_DIR/$1.state
  shift
  local IFS='|'
  printf '%s\n' "$*" >"$file.tmp" && mv -f -- "$file.tmp" "$file"
}

# write_result IMAGE STATUS ATTEMPTS OLD_ID NEW_ID START_MS MESSAGE
write_result() {
  local file=$WORK_DIR/$1.result
  now_ms
  printf 'status=%s\nattempts=%s\nold_id=%s\nnew_id=%s\nduration_ms=%s\nmessage=%s\n' \
    "$2" "$3" "$4" "$5" $((REPLY - $6)) "${7//$'\n'/ }" >"$file.tmp" && mv -f -- "$file.tmp" "$file"
}

# Runs in a background subshell: pulls one image with retries, logs to the
# image's log file, and always leaves a result file behind.
pull_worker() {
  local i=$1
  local ref=${IMG_REF[i]} attempt_log=$WORK_DIR/$i.attempt
  local child='' attempt=0 max=$((OPT_RETRIES + 1)) rc old_id='' new_id='' status start delay_ms delay
  now_ms
  start=$REPLY

  trap - EXIT
  trap '' INT # Ctrl-C is the parent's business; it stops us with SIGTERM
  trap 'if [[ -n $child ]]; then kill -TERM "$child" 2>/dev/null; wait "$child" 2>/dev/null; fi
    write_result "$i" cancelled "$attempt" "$old_id" "" "$start" "interrupted"
    exit 143' TERM HUP
  exec </dev/null >>"${IMG_LOG[i]}" 2>&1 3>&-
  if [[ -n $LOCK_FD ]]; then exec {LOCK_FD}>&-; fi

  old_id=$("${DOCKER[@]}" image inspect --format '{{.Id}}' "$ref" 2>/dev/null) || old_id=''
  printf '=== %s (local image: %s)\n' "$ref" "${old_id:-none}"

  while :; do
    attempt=$((attempt + 1))
    write_status "$i" pulling "$attempt"
    printf -- '--- attempt %d/%d at %(%F %T)T\n' "$attempt" "$max" -1
    "${PULL_CMD[@]}" "$ref" >"$attempt_log" 2>&1 &
    child=$!
    rc=0
    wait "$child" || rc=$?
    child=''
    cat -- "$attempt_log"
    if ((rc == 0)); then break; fi

    classify_pull_failure "$rc" "$attempt_log"
    if [[ $FAIL_CLASS == permanent ]] || ((attempt >= max)); then
      printf -- '--- giving up: %s\n' "$FAIL_MSG"
      write_result "$i" failed "$attempt" "$old_id" '' "$start" "$FAIL_MSG"
      exit 1
    fi
    backoff_ms "$attempt" "$FAIL_CLASS"
    delay_ms=$REPLY
    printf -v delay '%d.%03d' $((delay_ms / 1000)) $((delay_ms % 1000))
    now_ms
    write_status "$i" backoff "$attempt" $((REPLY + delay_ms))
    printf -- '--- %s; retrying in %ss\n' "$FAIL_MSG" "$delay"
    sleep "$delay" &
    child=$!
    wait "$child"
    child=''
  done

  new_id=$("${DOCKER[@]}" image inspect --format '{{.Id}}' "$ref" 2>/dev/null) || new_id=''
  status=unchanged
  if [[ $new_id != "$old_id" ]]; then status=updated; fi
  write_result "$i" "$status" "$attempt" "$old_id" "$new_id" "$start" ''
  exit 0
}

launch_worker() {
  local i=$1
  rm -f -- "$WORK_DIR/$i.result" "$WORK_DIR/$i.state"
  IMG_STATE[i]=pulling
  now_ms
  IMG_START_MS[i]=$REPLY
  pull_worker "$i" &
  RUNNING[$!]=$i
}

load_result() {
  local i=$1 key value
  if [[ ! -f $WORK_DIR/$i.result ]]; then
    # A worker stopped before it installed its TERM trap leaves no result.
    if ((ABORT_REQUESTED)); then
      set_state "$i" cancelled 'interrupted'
    else
      set_state "$i" failed 'pull worker exited unexpectedly'
    fi
    return 0
  fi
  while IFS='=' read -r key value; do
    case $key in
    status) IMG_STATE[i]=$value ;;
    attempts) IMG_ATTEMPTS[i]=$value ;;
    old_id) if [[ -n $value ]]; then IMG_LOCAL_ID[i]=$value; fi ;;
    new_id) IMG_NEW_ID[i]=$value ;;
    duration_ms) IMG_MS[i]=$value ;;
    message) IMG_NOTE[i]=$value ;;
    esac
  done <"$WORK_DIR/$i.result"
}

reap_worker() {
  local pid=$1 i=${RUNNING[$1]}
  unset 'RUNNING[$pid]'
  wait "$pid" 2>/dev/null
  load_result "$i"
  if ((!TUI_ACTIVE)); then print_progress "$i"; fi
}

# Non-blocking reap for the TUI loop.
reap_finished_workers() {
  local pid
  for pid in "${!RUNNING[@]}"; do
    if [[ -f $WORK_DIR/${RUNNING[$pid]}.result ]] || ! kill -0 "$pid" 2>/dev/null; then
      reap_worker "$pid"
    fi
  done
}

cancel_workers() {
  local pid i
  for pid in "${!RUNNING[@]}"; do kill -TERM "$pid" 2>/dev/null; done
  for pid in "${!RUNNING[@]}"; do reap_worker "$pid"; done
  for i in "${!IMG_STATE[@]}"; do
    if [[ ${IMG_STATE[i]} == queued ]]; then set_state "$i" cancelled 'not started'; fi
  done
}

# Pulls every queued image, at most OPT_JOBS at a time.
run_pulls() {
  local next=0 pid rc i
  local -a queue=()
  for i in "${!IMG_STATE[@]}"; do
    if [[ ${IMG_STATE[i]} == queued ]]; then queue+=("$i"); fi
  done
  while ((next < ${#queue[@]} || ${#RUNNING[@]} > 0)); do
    if ((ABORT_REQUESTED)); then
      cancel_workers
      break
    fi
    while ((${#RUNNING[@]} < OPT_JOBS && next < ${#queue[@]})); do
      launch_worker "${queue[next]}"
      next=$((next + 1))
    done
    if ((TUI_ACTIVE)); then
      tui_dashboard_tick
      reap_finished_workers
    else
      pid=''
      rc=0
      wait -n -p pid "${!RUNNING[@]}" || rc=$?
      if [[ -n ${pid:-} && -n ${RUNNING[$pid]:-} ]]; then
        reap_worker "$pid"
      elif ((rc == 127)); then
        reap_finished_workers # not our children any more; never spin on wait
      fi
    fi
  done
}

timed_run_pulls() {
  now_ms
  RUN_START_MS=$REPLY
  run_pulls
  now_ms
  RUN_ELAPSED_MS=$((RUN_ELAPSED_MS + REPLY - RUN_START_MS))
}

# ─── Reporting ───────────────────────────────────────────────────────────────

# id_change IMAGE -> REPLY, e.g. "4394114c33c1 → 00bf34fc5897".
id_change() {
  local old
  short_id "${IMG_LOCAL_ID[$1]}"
  old=${REPLY:-none}
  short_id "${IMG_NEW_ID[$1]}"
  REPLY="$old $GLYPH_ARROW $REPLY"
}

print_progress() {
  local i=$1 state=${IMG_STATE[$1]} detail='' took
  PROGRESS_DONE=$((PROGRESS_DONE + 1))
  if ((OPT_QUIET)) && [[ $state != failed ]]; then return 0; fi
  case $state in
  updated) id_change "$i" && detail=$REPLY ;;
  failed | cancelled) detail=${IMG_NOTE[i]} ;;
  esac
  if ((IMG_ATTEMPTS[i] > 1)); then detail+="${detail:+ }(attempt ${IMG_ATTEMPTS[i]})"; fi
  fmt_duration "${IMG_MS[i]}"
  took=$REPLY
  printf '%s[%*d/%d]%s %s%s %-9s%s %-*s %6s%s\n' "$C_DIM" ${#PROGRESS_TOTAL} "$PROGRESS_DONE" "$PROGRESS_TOTAL" \
    "$C_RESET" "${STYLE[${STATE_STYLE[$state]}]}" "${ICON[$state]}" "$state" "$C_RESET" \
    "$PROGRESS_REF_W" "${IMG_REF[i]}" "$took" "${detail:+  $detail}" >&3
}

report_add() {
  REPORT_STYLE+=("$1")
  REPORT_TEXT+=("$2")
}

# report_image IMAGE WIDTH STYLE ICON DETAIL
report_image() {
  local line
  printf -v line '  %s %-*s  %s' "$4" "$2" "${IMG_REF[$1]}" "$5"
  report_add "$3" "${line%"${line##*[! ]}"}"
}

report_log_tail() {
  local -a lines=()
  local line
  if [[ ! -r ${IMG_LOG[$1]} ]]; then return 0; fi
  mapfile -t lines <"${IMG_LOG[$1]}"
  for line in "${lines[@]: -4}"; do report_add dim "      | $line"; done
}

# redeploy_hint CONTAINER -> REPLY: how to put the new image into service.
redeploy_hint() {
  local c=$1 file cmd all_local=1
  local -a files=()
  IFS=, read -ra files <<<"${CTR_CONFIGS[c]}"
  if ((${#files[@]} == 0)); then all_local=0; fi
  printf -v cmd 'docker compose -p %q' "${CTR_PROJECT[c]}"
  if [[ -n ${CTR_WORKDIR[c]} && ${#files[@]} -gt 0 && ${CTR_WORKDIR[c]} != "${files[0]%/*}" ]]; then
    printf -v cmd '%s --project-directory %q' "$cmd" "${CTR_WORKDIR[c]}"
  fi
  for file in "${files[@]}"; do
    if [[ ! -f $file ]]; then all_local=0; fi
    printf -v cmd '%s -f %q' "$cmd" "$file"
  done
  if ((all_local)); then
    REPLY="$cmd up -d"
  elif [[ ${CTR_CONFIGS[c]} == /data/compose/* ]]; then
    REPLY='deployed by Portainer: redeploy the stack there'
  else
    REPLY='Compose files are not on this host: redeploy from whatever manages the stack'
  fi
}

report_stale() {
  local c i p line old new name_w=0 ref_w=0
  local -A by_project=()
  local -a projects=() members=()
  if ((${#STALE_CTRS[@]} == 0)); then return 0; fi
  for c in "${STALE_CTRS[@]}"; do
    by_project[${CTR_PROJECT[c]}]+=" $c"
    if ((${#CTR_NAME[c]} > name_w)); then name_w=${#CTR_NAME[c]}; fi
    if ((${#IMG_REF[CTR_IMG[c]]} > ref_w)); then ref_w=${#IMG_REF[CTR_IMG[c]]}; fi
  done
  report_add plain ''
  report_add warn "Outdated containers (${#STALE_CTRS[@]}): running an older image than their tag now points to; redeploy to apply."
  if ((OPT_QUIET)); then return 0; fi
  mapfile -t projects < <(printf '%s\n' "${!by_project[@]}" | LC_ALL=C sort)
  for p in "${projects[@]}"; do
    read -ra members <<<"${by_project[$p]}"
    c=${members[0]}
    report_add title "  $p${CTR_MATCH[c]:+  (${CTR_MATCH[c]})}"
    for c in "${members[@]}"; do
      i=${CTR_IMG[c]}
      short_id "${CTR_RUN_ID[c]}"
      old=$REPLY
      short_id "${IMG_NEW_ID[i]:-${IMG_LOCAL_ID[i]}}"
      new=$REPLY
      printf -v line '    %-*s  %-*s  %s %s %s' "$name_w" "${CTR_NAME[c]}" "$ref_w" "${IMG_REF[i]}" \
        "$old" "$GLYPH_ARROW" "$new"
      report_add plain "$line"
    done
    redeploy_hint "${members[0]}"
    report_add dim "    ${ICON[hint]} $REPLY"
  done
}

# project_counts MAP_NAME -> REPLY, e.g. "db (1 container), web (3 containers)".
project_counts() {
  local -n counts=$1
  local p n list=''
  sort_words "${!counts[@]}"
  for p in $REPLY; do
    n=${counts[$p]}
    list+="${list:+, }$p ($n container"
    if ((n > 1)); then list+=s; fi
    list+=')'
  done
  REPLY=$list
}

build_report() {
  local i w=0 unchanged=0 summary
  local -a updated_ix=() failed_ix=() skipped_ix=() excluded_ix=() cancelled_ix=() planned_ix=()
  REPORT_STYLE=() REPORT_TEXT=()
  for i in "${!IMG_REF[@]}"; do
    case ${IMG_STATE[i]} in
    updated) updated_ix+=("$i") ;;
    unchanged) unchanged=$((unchanged + 1)) ;;
    failed) failed_ix+=("$i") ;;
    skipped) skipped_ix+=("$i") ;;
    excluded) excluded_ix+=("$i") ;;
    cancelled) cancelled_ix+=("$i") ;;
    queued) planned_ix+=("$i") ;;
    esac
    if ((${#IMG_REF[i]} > w)); then w=${#IMG_REF[i]}; fi
  done
  if ((w > 56)); then w=56; fi

  if ((OPT_DRY_RUN)); then
    report_add title "Dry run: ${#planned_ix[@]} image(s) to pull, ${#skipped_ix[@]} skipped, ${#excluded_ix[@]} excluded."
    if ((!OPT_QUIET && ${#planned_ix[@]})); then
      report_add plain ''
      report_add head "Would pull (${#planned_ix[@]}):"
      for i in "${planned_ix[@]}"; do
        report_image "$i" "$w" plain "${ICON[queued]}" "${IMG_PROJECTS[i]// /, }"
      done
    fi
  else
    fmt_duration "$RUN_ELAPSED_MS"
    summary="Finished in $REPLY: ${#updated_ix[@]} updated, $unchanged unchanged, ${#failed_ix[@]} failed"
    if ((${#skipped_ix[@]})); then summary+=", ${#skipped_ix[@]} skipped"; fi
    if ((${#cancelled_ix[@]})); then summary+=", ${#cancelled_ix[@]} cancelled"; fi
    report_add title "$summary."
    if ((!OPT_QUIET && ${#updated_ix[@]})); then
      report_add plain ''
      report_add head "Updated (${#updated_ix[@]}):"
      for i in "${updated_ix[@]}"; do
        id_change "$i"
        report_image "$i" "$w" ok "${ICON[updated]}" "$REPLY  [${IMG_PROJECTS[i]// /, }]"
      done
    fi
    if ((${#failed_ix[@]})); then
      report_add plain ''
      report_add head "Failed (${#failed_ix[@]}):"
      for i in "${failed_ix[@]}"; do
        report_image "$i" "$w" err "${ICON[failed]}" "${IMG_NOTE[i]}"
        report_add dim "      log: ${IMG_LOG[i]}"
        if ((OPT_VERBOSE)); then report_log_tail "$i"; fi
      done
    fi
    if ((!OPT_QUIET && ${#cancelled_ix[@]})); then
      report_add plain ''
      report_add head "Cancelled (${#cancelled_ix[@]}):"
      for i in "${cancelled_ix[@]}"; do report_image "$i" "$w" warn "${ICON[cancelled]}" "${IMG_NOTE[i]}"; done
    fi
  fi

  if ((!OPT_QUIET && ${#skipped_ix[@]})); then
    report_add plain ''
    report_add head "Skipped (${#skipped_ix[@]}):"
    for i in "${skipped_ix[@]}"; do report_image "$i" "$w" dim "${ICON[skipped]}" "${IMG_NOTE[i]}"; done
  fi
  if ((!OPT_QUIET && ${#excluded_ix[@]})); then
    report_add plain ''
    if ((OPT_VERBOSE)); then
      report_add head "Excluded (${#excluded_ix[@]}):"
      for i in "${excluded_ix[@]}"; do report_image "$i" "$w" dim "${ICON[excluded]}" "${IMG_NOTE[i]}"; done
    else
      report_add dim "${#excluded_ix[@]} image(s) excluded by filters (-v lists them)."
    fi
  fi
  if ((!OPT_QUIET && (OPT_VERBOSE || OPT_DRY_RUN))); then
    if ((${#FILTERED_PROJECTS[@]})); then
      project_counts FILTERED_PROJECTS
      report_add plain ''
      report_add dim "Left out by project filters: $REPLY"
    fi
    if ((${#IGNORED_PROJECTS[@]})); then
      project_counts IGNORED_PROJECTS
      report_add plain ''
      report_add dim "Compose containers without a definition under ROOT (ignored): $REPLY"
    fi
  fi
  report_stale
}

print_report() {
  local k style
  for k in "${!REPORT_TEXT[@]}"; do
    style=${STYLE[${REPORT_STYLE[k]}]:-}
    printf '%s%s%s\n' "$style" "${REPORT_TEXT[k]}" "${style:+$C_RESET}" >&3
  done
}

emit_json() {
  local i c out items='' sep='' item status
  local -a words=() ctr_names=()
  json_str "$VERSION"
  out="{\"version\":$REPLY"
  json_str "$OPT_ROOT"
  out+=",\"root\":$REPLY"
  if ((OPT_DRY_RUN)); then out+=',"dry_run":true'; else out+=',"dry_run":false'; fi
  if ((ABORT_REQUESTED)); then out+=',"interrupted":true'; else out+=',"interrupted":false'; fi
  json_seconds "$RUN_ELAPSED_MS"
  out+=",\"duration_seconds\":$REPLY,\"summary\":{\"images\":${#IMG_REF[@]}"
  for status in updated unchanged failed skipped excluded cancelled; do
    count_state "$status"
    out+=",\"$status\":$REPLY"
  done
  count_state queued
  out+=",\"planned\":$((OPT_DRY_RUN ? REPLY : 0)),\"outdated_containers\":${#STALE_CTRS[@]}}"

  for i in "${!IMG_REF[@]}"; do
    status=${IMG_STATE[i]}
    if ((OPT_DRY_RUN)) && [[ $status == queued ]]; then status=planned; fi
    json_str "${IMG_REF[i]}"
    item="{\"ref\":$REPLY"
    json_str "${IMG_KEY[i]}"
    item+=",\"canonical\":$REPLY"
    json_str "$status"
    item+=",\"status\":$REPLY"
    json_str "${IMG_NOTE[i]}"
    item+=",\"note\":$REPLY"
    read -ra words <<<"${IMG_PROJECTS[i]}"
    json_list "${words[@]}"
    item+=",\"projects\":$REPLY"
    ctr_names=()
    read -ra words <<<"${IMG_CTRS[i]}"
    for c in "${words[@]}"; do ctr_names+=("${CTR_NAME[c]}"); done
    json_list "${ctr_names[@]}"
    item+=",\"containers\":$REPLY"
    json_str "${IMG_LOCAL_ID[i]}"
    item+=",\"local_id\":$REPLY"
    json_str "${IMG_NEW_ID[i]}"
    item+=",\"new_id\":$REPLY,\"attempts\":${IMG_ATTEMPTS[i]}"
    json_seconds "${IMG_MS[i]}"
    item+=",\"duration_seconds\":$REPLY"
    if ((KEEP_LOGS)) && [[ -f ${IMG_LOG[i]} ]]; then
      json_str "${IMG_LOG[i]}"
      item+=",\"log\":$REPLY}"
    else
      item+=',"log":null}'
    fi
    items+=$sep$item
    sep=,
  done
  out+=",\"images\":[$items]"

  items='' sep=''
  for c in "${STALE_CTRS[@]}"; do
    i=${CTR_IMG[c]}
    json_str "${CTR_NAME[c]}"
    item="{\"name\":$REPLY"
    json_str "${CTR_PROJECT[c]}"
    item+=",\"project\":$REPLY"
    json_str "${CTR_SERVICE[c]}"
    item+=",\"service\":$REPLY"
    json_str "${IMG_REF[i]}"
    item+=",\"image\":$REPLY"
    json_str "${CTR_RUN_ID[c]}"
    item+=",\"running_id\":$REPLY"
    json_str "${IMG_NEW_ID[i]:-${IMG_LOCAL_ID[i]}}"
    item+=",\"latest_id\":$REPLY"
    json_str "${CTR_MATCH[c]}"
    item+=",\"compose_file\":$REPLY}"
    items+=$sep$item
    sep=,
  done
  out+=",\"outdated_containers\":[$items]}"
  printf '%s\n' "$out"
}

# ─── TUI ─────────────────────────────────────────────────────────────────────

TUI_ACTIVE=0 TUI_RESIZED=0 TUI_W=80 TUI_H=24 TUI_BUF='' TUI_STTY=''
TUI_TOP=0 TUI_CURSOR=0 TUI_PAGE=10 TUI_SCROLL_MAX=0 TUI_CONFIRM=0 TUI_FILTER='' TUI_MSG=''
TUI_REF_MAX=20 # widest image reference on offer
KEY=''
ORDER=() VIEW=() RUN_SET=() SEGS=()
declare -A LAYER_INFO=() LAYER_AT=()

tui_init() {
  TUI_STTY=$(stty -g 2>/dev/null) || TUI_STTY=''
  stty -echo -icanon 2>/dev/null
  printf '\e[?1049h\e[?7l\e[?25l\e[2J'
  TUI_ACTIVE=1
  tui_size
  trap 'TUI_RESIZED=1' WINCH
  trap '' TSTP # suspending from the alternate screen would leave the terminal in a mess
}

tui_leave() {
  if ((!TUI_ACTIVE)); then return 0; fi
  TUI_ACTIVE=0
  trap - WINCH TSTP
  printf '\e[0m\e[?25h\e[?7h\e[?1049l'
  if [[ -n $TUI_STTY ]]; then stty "$TUI_STTY" 2>/dev/null; fi
  return 0
}

tui_size() {
  local rows='' cols=''
  read -r rows cols < <(stty size 2>/dev/null)
  if [[ $rows =~ ^[1-9][0-9]*$ && $cols =~ ^[1-9][0-9]*$ ]]; then
    TUI_H=$rows TUI_W=$cols
  fi
}

# tui_read_key TIMEOUT -> KEY; fails when no key arrives in time.
tui_read_key() {
  local k='' c=''
  KEY=''
  if ! IFS= read -rsN1 -t "$1" k; then return 1; fi
  if [[ $k == $'\e' ]] && IFS= read -rsN1 -t 0.02 c; then
    k+=$c
    if [[ $c == '[' || $c == O ]]; then # CSI/SS3: read up to the final byte
      while IFS= read -rsN1 -t 0.02 c; do
        k+=$c
        if [[ $c != [0-9\;] ]]; then break; fi
      done
    fi
  fi
  KEY=$k
  return 0
}

# tui_nav KEY VALUE COUNT -> REPLY: VALUE moved by a navigation key, clamped to
# 0..COUNT-1; fails when KEY is not a navigation key.
tui_nav() {
  local v=$2 n=$3
  case $1 in
  $'\e[A' | $'\eOA' | k) v=$((v - 1)) ;;
  $'\e[B' | $'\eOB' | j) v=$((v + 1)) ;;
  $'\e[5~' | $'\x02') v=$((v - TUI_PAGE)) ;;
  $'\e[6~' | $'\x06' | ' ') v=$((v + TUI_PAGE)) ;;
  $'\e[H' | $'\e[1~' | $'\eOH' | g) v=0 ;;
  $'\e[F' | $'\e[4~' | $'\eOF' | G) v=$((n - 1)) ;;
  *) return 1 ;;
  esac
  if ((v > n - 1)); then v=$((n - 1)); fi
  if ((v < 0)); then v=0; fi
  REPLY=$v
}

tui_frame_begin() {
  if ((TUI_RESIZED)); then
    TUI_RESIZED=0
    tui_size
    TUI_BUF=$'\e[2J'
  else
    TUI_BUF=''
  fi
  if ((TUI_W < 60 || TUI_H < 10)); then
    printf '%s\e[H\e[2J%s' "$TUI_BUF" "Terminal too small (${TUI_W}x${TUI_H}); 60x10 needed. q quits."
    return 1
  fi
  TUI_PAGE=$((TUI_H > 8 ? TUI_H - 6 : 1))
}

tui_frame_end() { printf '%s' "$TUI_BUF"; }

tui_put() { TUI_BUF+=$'\e['"$1"$';1H'"$2"$'\e[0m\e[K'; }

# tui_put_segments ROW STYLE TEXT [STYLE TEXT]...: one row built from styled
# pieces, cut off at the terminal width.
tui_put_segments() {
  local row=$1 out='' left=$TUI_W text
  shift
  while (($# >= 2 && left > 0)); do
    text=$2
    if ((${#text} > left)); then text=${text:0:left}; fi
    out+=${STYLE[$1]:-}$text$C_RESET
    left=$((left - ${#text}))
    shift 2
  done
  tui_put "$row" "$out"
}

# tui_bar ROW LEFT RIGHT: a full-width title bar.
tui_bar() {
  local left=$2 right=$3 gap
  gap=$((TUI_W - ${#left} - ${#right}))
  if ((gap < 1)); then
    fit "$left" $((TUI_W - ${#right} - 1))
    left=$REPLY
    gap=1
  fi
  printf -v REPLY '%s%*s%s' "$left" "$gap" '' "$right"
  fit "$REPLY" "$TUI_W"
  tui_put "$1" "${STYLE[bar]}$REPLY"
}

# Selection order: grouped by (first) project, then by reference.
tui_build_order() {
  local i line
  local -a lines=()
  ORDER=()
  for i in "${!IMG_REF[@]}"; do
    if [[ ${IMG_STATE[i]} != excluded ]]; then
      lines+=("${IMG_PROJECTS[i]%% *}$SEP${IMG_REF[i]}$SEP$i")
      if ((${#IMG_REF[i]} > TUI_REF_MAX)); then TUI_REF_MAX=${#IMG_REF[i]}; fi
    fi
  done
  if ((${#lines[@]} == 0)); then return 0; fi
  while IFS= read -r line; do
    ORDER+=("${line##*"$SEP"}")
  done < <(printf '%s\n' "${lines[@]}" | LC_ALL=C sort)
}

tui_filter_view() {
  local i haystack needle=${TUI_FILTER,,}
  VIEW=()
  for i in "${ORDER[@]}"; do
    haystack="${IMG_REF[i]} ${IMG_PROJECTS[i]}"
    if [[ -z $needle || ${haystack,,} == *"$needle"* ]]; then VIEW+=("$i"); fi
  done
}

# image_note IMAGE -> REPLY: the short note shown in the selection list.
image_note() {
  local i=$1 note=''
  case ${IMG_KIND[i]} in
  pinned) note='pinned' ;;
  local) note='local build' ;;
  id) note='image ID' ;;
  esac
  if [[ -z ${IMG_LOCAL_ID[i]} ]]; then note='not present'; fi
  if ((IMG_STALE[i])); then note+="${note:+ $GLYPH_SEP }${IMG_STALE[i]} outdated"; fi
  REPLY=$note
}

tui_image_detail() {
  local i=$1 c users=''
  local -a ctrs=()
  read -ra ctrs <<<"${IMG_CTRS[i]}"
  for c in "${ctrs[@]}"; do users+=${users:+, }${CTR_NAME[c]}; done
  short_id "${IMG_LOCAL_ID[i]}"
  REPLY="used by $users $GLYPH_SEP local ${REPLY:-none}"
  if [[ ${IMG_STATE[i]} == skipped ]]; then REPLY+=" $GLYPH_SEP ${IMG_NOTE[i]}"; fi
  if ((IMG_STALE[i])); then REPLY+=" $GLYPH_SEP ${IMG_STALE[i]} container(s) run an older image"; fi
}

tui_render_select() {
  local filtering=$1 list_h n sel=0 i row pos proj_w ref_w note_w box box_style ref proj note note_style style line
  tui_frame_begin || return 0
  list_h=$((TUI_H - 4))
  n=${#VIEW[@]}
  for i in "${ORDER[@]}"; do sel=$((sel + IMG_SEL[i])); done
  if ((TUI_CURSOR >= n)); then TUI_CURSOR=$((n > 0 ? n - 1 : 0)); fi
  if ((TUI_CURSOR < TUI_TOP)); then TUI_TOP=$TUI_CURSOR; fi
  if ((TUI_CURSOR >= TUI_TOP + list_h)); then TUI_TOP=$((TUI_CURSOR - list_h + 1)); fi

  # Columns: " ▸ [x] " IMAGE "  " PROJECT "  " NOTE; NOTE takes what is left.
  proj_w=$(((TUI_W - 30) / 4))
  if ((proj_w > 22)); then proj_w=22; fi
  ref_w=$((TUI_W - 30 - proj_w))
  if ((ref_w > TUI_REF_MAX)); then ref_w=$TUI_REF_MAX; fi
  note_w=$((TUI_W - 11 - ref_w - proj_w))

  tui_bar 1 " pull-image $GLYPH_SEP choose images to pull" "$sel of ${#ORDER[@]} selected "
  fit IMAGE "$ref_w"
  line="       $REPLY  "
  fit PROJECT "$proj_w"
  line+="$REPLY  NOTE"
  tui_put_segments 2 dim "$line"

  for ((row = 0; row < list_h; row++)); do
    pos=$((TUI_TOP + row))
    if ((pos >= n)); then
      tui_put $((row + 3)) ''
      continue
    fi
    i=${VIEW[pos]}
    box='[ ]' style=dim
    if ((IMG_SEL[i])); then box='[x]' style=plain; fi
    fit_mid "${IMG_REF[i]}" "$ref_w"
    ref=$REPLY
    fit "${IMG_PROJECTS[i]// /, }" "$proj_w"
    proj=$REPLY
    image_note "$i"
    fit "$REPLY" "$note_w"
    note=$REPLY
    if ((pos == TUI_CURSOR)); then
      fit " $GLYPH_POINTER $box $ref  $proj  $note" "$TUI_W"
      tui_put_segments $((row + 3)) cursor "$REPLY"
    else
      box_style=dim note_style=dim
      if ((IMG_SEL[i])); then box_style=ok; fi
      if ((IMG_STALE[i])); then note_style=warn; fi
      tui_put_segments $((row + 3)) plain '   ' "$box_style" "$box" "$style" " $ref  " dim "$proj  " \
        "$note_style" "$note"
    fi
  done

  if ((n > 0)); then
    tui_image_detail "${VIEW[TUI_CURSOR]}"
    tui_put_segments $((TUI_H - 1)) dim " $REPLY"
  elif [[ -n $TUI_FILTER ]]; then
    tui_put_segments $((TUI_H - 1)) warn " No image matches '$TUI_FILTER'."
  else
    tui_put $((TUI_H - 1)) ''
  fi
  if ((filtering)); then
    tui_put_segments "$TUI_H" title " filter: " plain "$TUI_FILTER" cursor ' ' dim "   enter keeps it $GLYPH_SEP esc clears"
  elif [[ -n $TUI_MSG ]]; then
    tui_put_segments "$TUI_H" warn " $TUI_MSG"
  else
    tui_put_segments "$TUI_H" dim " ↑↓ move  space toggle  p project  a all  n none  i invert  / filter  enter pull  q quit"
  fi
  tui_frame_end
}

# tui_select: 0 = pull the selection, 1 = quit, 2 = interrupted.
tui_select() {
  local filtering=0 n i v project
  TUI_FILTER='' TUI_CURSOR=0 TUI_TOP=0 TUI_MSG=''
  tui_filter_view
  while :; do
    if ((ABORT_REQUESTED)); then return 2; fi
    tui_render_select "$filtering"
    TUI_MSG=''
    if ! tui_read_key 1; then continue; fi
    n=${#VIEW[@]}
    if ((filtering)); then
      case $KEY in
      $'\n' | $'\r') filtering=0 ;;
      $'\e') filtering=0 TUI_FILTER='' ;;
      $'\x7f' | $'\b') TUI_FILTER=${TUI_FILTER%?} ;;
      [[:print:]]) TUI_FILTER+=$KEY ;;
      esac
      tui_filter_view
      TUI_CURSOR=0 TUI_TOP=0
      continue
    fi
    case $KEY in
    ' ')
      if ((n)); then
        i=${VIEW[TUI_CURSOR]}
        IMG_SEL[i]=$((1 - IMG_SEL[i]))
        if ((TUI_CURSOR + 1 < n)); then TUI_CURSOR=$((TUI_CURSOR + 1)); fi
      fi
      ;;
    a) for i in "${VIEW[@]}"; do IMG_SEL[i]=1; done ;;
    n) for i in "${VIEW[@]}"; do IMG_SEL[i]=0; done ;;
    i) for i in "${VIEW[@]}"; do IMG_SEL[i]=$((1 - IMG_SEL[i])); done ;;
    p)
      if ((n)); then
        i=${VIEW[TUI_CURSOR]}
        project=${IMG_PROJECTS[i]%% *}
        v=$((1 - IMG_SEL[i]))
        for i in "${ORDER[@]}"; do
          if [[ " ${IMG_PROJECTS[i]} " == *" $project "* ]]; then IMG_SEL[i]=$v; fi
        done
      fi
      ;;
    /) filtering=1 ;;
    $'\n' | $'\r')
      v=0
      for i in "${ORDER[@]}"; do v=$((v + IMG_SEL[i])); done
      if ((v)); then return 0; fi
      TUI_MSG='Nothing selected: space toggles an image, a selects all.'
      ;;
    q | Q | $'\e') return 1 ;;
    *) if tui_nav "$KEY" "$TUI_CURSOR" "$n"; then TUI_CURSOR=$REPLY; fi ;;
    esac
  done
}

# layer_progress IMAGE NOW -> REPLY "done/total" layers of the current attempt
# (parsed from docker's plain-text progress; refreshed at most every 300ms).
layer_progress() {
  local i=$1 now=$2 file=$WORK_DIR/$1.attempt line id total=0 complete=0
  local -A layers=()
  if ((now - ${LAYER_AT[$i]:-0} < 300)); then
    REPLY=${LAYER_INFO[$i]:-}
    return 0
  fi
  LAYER_AT[$i]=$now
  if [[ -r $file ]]; then
    while IFS= read -r line; do
      id=${line%%: *}
      if ((${#id} == 12)) && [[ $id != *[!0-9a-f]* ]]; then layers[$id]=${line#*: }; fi
    done <"$file"
  fi
  for id in "${!layers[@]}"; do
    total=$((total + 1))
    case ${layers[$id]} in 'Pull complete' | 'Already exists') complete=$((complete + 1)) ;; esac
  done
  REPLY=''
  if ((total)); then REPLY="$complete/$total"; fi
  LAYER_INFO[$i]=$REPLY
}

# tui_job_row IMAGE NOW REF_W PROJ_W INFO_W -> SEGS (for tui_put_segments).
tui_job_row() {
  local i=$1 now=$2 state=${IMG_STATE[$1]} icon label style info='' time=''
  local phase='' attempt=0 deadline=0
  style=${STATE_STYLE[$state]:-plain}
  icon=${ICON[$state]:-?}
  label=$state
  case $state in
  pulling)
    icon=${SPINNER[now / 100 % ${#SPINNER[@]}]}
    if [[ -r $WORK_DIR/$i.state ]]; then IFS='|' read -r phase attempt deadline <"$WORK_DIR/$i.state"; fi
    if [[ $phase == backoff ]]; then
      label=retrying style=warn icon=${ICON[retry]}
      info="attempt $attempt failed; next in $(((deadline - now + 999) / 1000))s"
    else
      layer_progress "$i" "$now"
      info=${REPLY:+layers $REPLY}
      info=${info:-resolving}
      if ((attempt > 1)); then info="attempt $attempt/$((OPT_RETRIES + 1)) $GLYPH_SEP $info"; fi
    fi
    fmt_clock $((now - IMG_START_MS[i]))
    time=$REPLY
    ;;
  updated) id_change "$i" && info=$REPLY ;;
  failed | cancelled) info=${IMG_NOTE[i]} ;;
  esac
  case $state in
  updated | unchanged | failed | cancelled)
    if ((IMG_ATTEMPTS[i] > 1)); then info+="${info:+ }(attempt ${IMG_ATTEMPTS[i]})"; fi
    fmt_duration "${IMG_MS[i]}"
    time=$REPLY
    ;;
  esac
  fit_mid "${IMG_REF[i]}" "$3"
  local ref=$REPLY
  fit "${IMG_PROJECTS[i]// /, }" "$4"
  local proj=$REPLY
  fit "$info" "$5"
  info=$REPLY
  printf -v time '%7s' "$time"
  fit "$label" 9
  SEGS=("$style" " $icon $REPLY " plain "$ref  " dim "$proj  " "$style" "$info " dim "$time")
}

tui_render_dashboard() {
  local list_h n now i row pos total=${#RUN_SET[@]} finished n_running n_updated n_unchanged n_failed n_cancelled
  local ref_w proj_w info_w avail bar_w filled bar
  local -a rows=() active=() bad=() good=() waiting=() same=() other=()
  tui_frame_begin || return 0
  now_ms
  now=$REPLY
  for i in "${RUN_SET[@]}"; do
    case ${IMG_STATE[i]} in
    pulling) active+=("$i") ;;
    failed) bad+=("$i") ;;
    updated) good+=("$i") ;;
    queued) waiting+=("$i") ;;
    unchanged) same+=("$i") ;;
    *) other+=("$i") ;;
    esac
  done
  n_running=${#active[@]} n_failed=${#bad[@]} n_updated=${#good[@]} n_unchanged=${#same[@]} n_cancelled=${#other[@]}
  finished=$((n_updated + n_unchanged + n_failed + n_cancelled))
  rows=("${active[@]}" "${bad[@]}" "${good[@]}" "${waiting[@]}" "${same[@]}" "${other[@]}")
  n=${#rows[@]}
  list_h=$((TUI_H - 4))
  TUI_SCROLL_MAX=$((n > list_h ? n - list_h : 0))
  if ((TUI_TOP > TUI_SCROLL_MAX)); then TUI_TOP=$TUI_SCROLL_MAX; fi

  fmt_clock $((now - RUN_START_MS))
  tui_bar 1 " pull-image $GLYPH_SEP pulling $total image(s), $((OPT_JOBS < total ? OPT_JOBS : total)) at a time" \
    "elapsed $REPLY "

  bar_w=$((TUI_W / 4 > 40 ? 40 : TUI_W / 4))
  filled=$((total ? finished * bar_w / total : bar_w))
  printf -v bar '%*s' "$filled" ''
  bar=${bar// /$GLYPH_FULL}
  printf -v REPLY '%*s' $((bar_w - filled)) ''
  bar+=${REPLY// /$GLYPH_EMPTY}
  SEGS=(info " $bar " title "$finished/$total " info "  $n_running running"
    ok "  ${ICON[updated]} $n_updated updated" dim "  ${ICON[unchanged]} $n_unchanged unchanged"
    err "  ${ICON[failed]} $n_failed failed")
  if ((n_cancelled)); then SEGS+=(warn "  ${ICON[cancelled]} $n_cancelled cancelled"); fi
  tui_put_segments 2 "${SEGS[@]}"

  avail=$((TUI_W - 27))
  ref_w=$((avail * 45 / 100))
  if ((ref_w > TUI_REF_MAX)); then ref_w=$TUI_REF_MAX; fi
  proj_w=$((avail / 5 > 18 ? 18 : avail / 5))
  info_w=$((avail - ref_w - proj_w))
  fit STATUS 9
  local header="   $REPLY "
  fit IMAGE "$ref_w"
  header+="$REPLY  "
  fit PROJECT "$proj_w"
  header+="$REPLY  "
  fit DETAIL "$info_w"
  header+="$REPLY    TIME"
  tui_put_segments 3 dim "$header"

  for ((row = 0; row < list_h; row++)); do
    pos=$((TUI_TOP + row))
    if ((pos >= n)); then
      tui_put $((row + 4)) ''
      continue
    fi
    tui_job_row "${rows[pos]}" "$now" "$ref_w" "$proj_w" "$info_w"
    tui_put_segments $((row + 4)) "${SEGS[@]}"
  done

  if ((ABORT_REQUESTED)); then
    tui_put_segments "$TUI_H" warn " Stopping running pulls${GLYPH_ELLIPSIS}"
  elif ((TUI_CONFIRM)); then
    tui_put_segments "$TUI_H" warn " Abort? Running pulls are stopped, queued ones skipped. [y/N] "
  else
    tui_put_segments "$TUI_H" dim " ↑↓ PgUp PgDn scroll  q abort"
  fi
  tui_frame_end
}

tui_dashboard_tick() {
  tui_render_dashboard
  if ! tui_read_key 0.12; then return 0; fi
  if ((TUI_CONFIRM)); then
    TUI_CONFIRM=0
    if [[ $KEY == [yY] ]]; then ABORT_REQUESTED=1; fi
    return 0
  fi
  case $KEY in
  q | Q) TUI_CONFIRM=1 ;;
  *) if tui_nav "$KEY" "$TUI_TOP" $((TUI_SCROLL_MAX + 1)); then TUI_TOP=$REPLY; fi ;;
  esac
}

tui_render_results() {
  local n_failed=$1 list_h n row pos right=''
  tui_frame_begin || return 0
  list_h=$((TUI_H - 2))
  n=${#REPORT_TEXT[@]}
  TUI_SCROLL_MAX=$((n > list_h ? n - list_h : 0))
  if ((TUI_TOP > TUI_SCROLL_MAX)); then TUI_TOP=$TUI_SCROLL_MAX; fi
  if ((${#WARNINGS[@]})); then right="${#WARNINGS[@]} warning(s) "; fi
  tui_bar 1 " pull-image $GLYPH_SEP results" "$right"
  for ((row = 0; row < list_h; row++)); do
    pos=$((TUI_TOP + row))
    if ((pos < n)); then
      tui_put_segments $((row + 2)) "${REPORT_STYLE[pos]}" " ${REPORT_TEXT[pos]}"
    else
      tui_put $((row + 2)) ''
    fi
  done
  if ((n_failed)); then
    tui_put_segments "$TUI_H" dim " ↑↓ PgUp PgDn scroll  " warn "r retry $n_failed failed" dim "  q quit"
  else
    tui_put_segments "$TUI_H" dim " ↑↓ PgUp PgDn scroll  q quit"
  fi
  tui_frame_end
}

# tui_results: 0 = retry the failed pulls, 1 = leave.
tui_results() {
  local n_failed=0 i
  for i in "${RUN_SET[@]}"; do
    if [[ ${IMG_STATE[i]} == failed ]]; then n_failed=$((n_failed + 1)); fi
  done
  TUI_TOP=0
  while :; do
    if ((ABORT_REQUESTED)); then
      ABORT_REQUESTED=0 # nothing left to abort: Ctrl-C just closes the screen
      return 1
    fi
    tui_render_results "$n_failed"
    if ! tui_read_key 1; then continue; fi
    case $KEY in
    r | R) if ((n_failed)); then return 0; fi ;;
    q | Q | $'\e' | $'\n' | $'\r') return 1 ;;
    *) if tui_nav "$KEY" "$TUI_TOP" $((TUI_SCROLL_MAX + 1)); then TUI_TOP=$REPLY; fi ;;
    esac
  done
}

tui_main() {
  local i rc warning
  for i in "${!IMG_REF[@]}"; do
    IMG_SEL[i]=0
    if [[ ${IMG_STATE[i]} == queued ]]; then IMG_SEL[i]=1; fi
  done
  tui_build_order
  if ((${#ORDER[@]} == 0)); then
    say 'Nothing to choose from: every image is excluded by filters.'
    return 0
  fi

  INTERRUPTIBLE=1
  tui_init
  rc=0
  tui_select || rc=$?
  if ((rc != 0)); then
    tui_leave
    say 'Nothing was pulled.'
    return 0
  fi
  RUN_SET=()
  for i in "${ORDER[@]}"; do
    if ((IMG_SEL[i])); then
      set_state "$i" queued ''
      RUN_SET+=("$i")
    elif [[ ${IMG_STATE[i]} == queued ]]; then
      set_state "$i" skipped 'not selected'
    fi
  done

  if ((OPT_DRY_RUN)); then
    tui_leave
    build_report
    print_report
    return 0
  fi

  while :; do
    TUI_CONFIRM=0 TUI_TOP=0
    timed_run_pulls
    finish_run
    if ((ABORT_REQUESTED)); then break; fi
    tui_results || break
    for i in "${RUN_SET[@]}"; do
      if [[ ${IMG_STATE[i]} == failed ]]; then set_state "$i" queued ''; fi
    done
  done
  INTERRUPTIBLE=0
  tui_leave
  print_report
  for warning in "${WARNINGS[@]}"; do warn "$warning"; done
}

# ─── Main ────────────────────────────────────────────────────────────────────

# on_signal SIGNAL
on_signal() {
  local pid
  ABORT_SIGNAL=${ABORT_SIGNAL:-$1}
  if ((ABORT_REQUESTED || !INTERRUPTIBLE)); then
    # Second interrupt, or nothing to wind down: leave right away.
    for pid in "${!RUNNING[@]}"; do kill -KILL "$pid" 2>/dev/null; done
    exit "$EXIT_INTERRUPTED"
  fi
  ABORT_REQUESTED=1
}

on_exit() {
  local pid
  for pid in "${!RUNNING[@]}"; do kill -TERM "$pid" 2>/dev/null; done
  tui_leave
  if [[ -n $WORK_DIR && -d $WORK_DIR ]]; then
    if ((KEEP_LOGS)) && [[ $LOG_DIR == "$WORK_DIR"/* ]]; then
      find "$WORK_DIR" -maxdepth 1 -type f -delete 2>/dev/null # keep only logs/
    else
      rm -rf -- "$WORK_DIR"
    fi
  fi
  # Die of SIGINT ourselves so a calling shell or loop knows Ctrl-C was pressed.
  if [[ $ABORT_SIGNAL == INT ]] && ((ABORT_REQUESTED)); then
    trap - INT EXIT
    kill -INT $$
  fi
}

finish_run() {
  local i
  compute_stale
  for i in "${!IMG_STATE[@]}"; do
    if [[ ${IMG_STATE[i]} == failed ]]; then KEEP_LOGS=1; fi
  done
  build_report
}

plain_main() {
  local i
  count_state queued
  PROGRESS_TOTAL=$REPLY PROGRESS_DONE=0 PROGRESS_REF_W=0
  for i in "${!IMG_REF[@]}"; do
    if [[ ${IMG_STATE[i]} == queued ]] && ((${#IMG_REF[i]} > PROGRESS_REF_W)); then
      PROGRESS_REF_W=${#IMG_REF[i]}
    fi
  done
  if ((PROGRESS_REF_W > 56)); then PROGRESS_REF_W=56; fi
  if ((PROGRESS_TOTAL > 0)); then
    info "Pulling $PROGRESS_TOTAL image(s), up to $OPT_JOBS at a time."
  fi

  INTERRUPTIBLE=1
  timed_run_pulls
  INTERRUPTIBLE=0
  finish_run
  if ((PROGRESS_TOTAL > 0)) && ((!OPT_QUIET)); then say ''; fi
  print_report
  if ((OPT_JSON)); then emit_json; fi
}

exit_status() {
  local i
  if ((ABORT_REQUESTED)); then return "$EXIT_INTERRUPTED"; fi
  for i in "${!IMG_STATE[@]}"; do
    if [[ ${IMG_STATE[i]} == failed ]]; then return "$EXIT_FAILED"; fi
  done
  return "$EXIT_OK"
}

main() {
  parse_args "$@"
  setup_output
  trap on_exit EXIT
  trap 'on_signal INT' INT
  trap 'on_signal TERM' TERM
  trap 'on_signal HUP' HUP
  load_ignore_file
  preflight
  discover
  plan_images
  compute_stale

  if ((${#IMG_REF[@]} == 0)); then
    info "No Compose containers matched definitions under $OPT_ROOT."
    if ((OPT_JSON)); then emit_json; fi
    return "$EXIT_OK"
  fi
  local c
  local -A projects=()
  for c in "${!CTR_PROJECT[@]}"; do projects[${CTR_PROJECT[c]}]=1; done
  info "Found ${#IMG_REF[@]} image(s) used by ${#CTR_NAME[@]} container(s) in ${#projects[@]} project(s); $COMPOSE_FILE_COUNT Compose file(s) under $OPT_ROOT."

  if ((OPT_DRY_RUN && !OPT_TUI)); then
    build_report
    print_report
    if ((OPT_JSON)); then emit_json; fi
    return "$EXIT_OK"
  fi

  if ((!OPT_DRY_RUN)); then
    acquire_lock
    check_disk_space
    prepare_workdir
  fi
  if ((OPT_TUI)); then tui_main; else plain_main; fi
  exit_status
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
  exit $?
fi
