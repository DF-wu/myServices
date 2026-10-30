#!/usr/bin/env bats
#
# Tests for pull-image.sh. They drive the script against tests/fixtures/fake-docker,
# so no Docker daemon or network is needed.
#
#   bats tests/pull-image.bats
#   docker run --rm -v "$PWD:/code" -w /code bats/bats:latest tests/pull-image.bats

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT=$BATS_TEST_DIRNAME/../pull-image.sh
  ROOT=$BATS_TEST_TMPDIR/root
  FAKE_DOCKER_DIR=$BATS_TEST_TMPDIR/docker
  mkdir -p "$ROOT" "$FAKE_DOCKER_DIR/tags"
  : >"$FAKE_DOCKER_DIR/containers"
  : >"$FAKE_DOCKER_DIR/images"
  : >"$FAKE_DOCKER_DIR/pulls"

  export FAKE_DOCKER_DIR
  export DOCKER_BIN=$BATS_TEST_DIRNAME/fixtures/fake-docker
  export PULL_IMAGE_ROOT=$ROOT
  export PULL_IMAGE_LOCK=$BATS_TEST_TMPDIR/pull-image.lock
  export PULL_IMAGE_BACKOFF_MS=0
  export PULL_IMAGE_MIN_FREE_GB=0
  export TMPDIR=$BATS_TEST_TMPDIR
  export NO_COLOR=1
  unset PULL_IMAGE_JOBS PULL_IMAGE_RETRIES PULL_IMAGE_TIMEOUT PULL_IMAGE_LOG_DIR
}

compose_file() {
  mkdir -p "$ROOT/$(dirname "$1")"
  printf 'services: {}\n' >"$ROOT/$1"
}

container() { printf '%s\n' "$1" >>"$FAKE_DOCKER_DIR/containers"; }

local_image() { printf '%s\n' "$1" >>"$FAKE_DOCKER_DIR/images"; }

tag() { printf '%s\n' "$2" >"$FAKE_DOCKER_DIR/tags/${1//\//_}"; }

pulls() { printf '%s|%s\n' "$1" "$2" >>"$FAKE_DOCKER_DIR/pulls"; }

pull_count() { grep -c "^pull $1\$" "$FAKE_DOCKER_DIR/calls" || true; }

# web (in the repo), db (a Portainer git stack of the repo), a local build, a
# digest-pinned image and a foreign project that must be left alone.
standard_scenario() {
  compose_file web/docker-compose.yml
  compose_file _FORMAL/db/compose.yaml
  compose_file builder/docker-compose.yml
  container "web-app|nginx:latest|sha256:nginx-1|web|app|$ROOT/web|$ROOT/web/docker-compose.yml"
  container "web-cache|redis|sha256:redis-1|web|cache|$ROOT/web|$ROOT/web/docker-compose.yml"
  container "web-tool|ghcr.io/acme/tool:1.0@sha256:abc|sha256:tool-1|web|tool|$ROOT/web|$ROOT/web/docker-compose.yml"
  container "db|docker.io/library/redis:latest|sha256:redis-1|db|db|/data/compose/7/_FORMAL/db|/data/compose/7/_FORMAL/db/compose.yaml"
  container "builder|myapp:dev|sha256:local-1|builder|app|$ROOT/builder|$ROOT/builder/docker-compose.yml"
  container "stranger|busybox:latest|sha256:bb-1|other|x|/opt/other|/opt/other/docker-compose.yml"
  local_image "nginx|latest|sha256:dg-nginx|sha256:nginx-1"
  local_image "redis|latest|sha256:dg-redis|sha256:redis-1"
  local_image "ghcr.io/acme/tool|<none>|sha256:abc|sha256:tool-1"
  local_image "myapp|dev|<none>|sha256:local-1"
  local_image "busybox|latest|sha256:dg-bb|sha256:bb-1"
  tag nginx:latest sha256:nginx-1
  tag redis sha256:redis-1
  tag busybox:latest sha256:bb-1
}

# ─── Unit tests (functions sourced in a subshell) ───────────────────────────

@test "normalize_ref resolves Docker's implicit registry, namespace and tag" {
  run bash -c '
    source "$1"
    for ref in redis redis:7 docker.io/library/redis index.docker.io/library/redis:latest \
      valkey/valkey:8-alpine docker.io/valkey/valkey:8-alpine ghcr.io/a/b localhost:5000/x \
      localhost/x:1 docker.n8n.io/n8nio/n8n "repo:1.0@sha256:abc"; do
      normalize_ref "$ref"
      printf "%s\n" "$REPLY"
    done' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = docker.io/library/redis:latest ]
  [ "${lines[1]}" = docker.io/library/redis:7 ]
  [ "${lines[2]}" = docker.io/library/redis:latest ]
  [ "${lines[3]}" = docker.io/library/redis:latest ]
  [ "${lines[4]}" = docker.io/valkey/valkey:8-alpine ]
  [ "${lines[5]}" = docker.io/valkey/valkey:8-alpine ]
  [ "${lines[6]}" = ghcr.io/a/b:latest ]
  [ "${lines[7]}" = localhost:5000/x:latest ]
  [ "${lines[8]}" = localhost/x:1 ]
  [ "${lines[9]}" = docker.n8n.io/n8nio/n8n:latest ]
  [ "${lines[10]}" = docker.io/library/repo@sha256:abc ]
}

@test "classify_pull_failure separates permanent, rate-limit and transient errors" {
  run bash -c '
    source "$1"
    log=$2/log
    check() { printf "%s\n" "$2" >"$log"; classify_pull_failure "$1" "$log"; printf "%s|%s\n" "$FAIL_CLASS" "$FAIL_MSG"; }
    check 1 "Error response from daemon: pull access denied for x, repository does not exist"
    check 1 "Error response from daemon: manifest for x:9 not found: manifest unknown: manifest unknown"
    check 1 "Error response from daemon: toomanyrequests: You have reached your pull rate limit."
    check 1 "Error response from daemon: Get \"https://ghcr.io/v2/\": net/http: TLS handshake timeout"
    OPT_TIMEOUT=5; check 124 ""' _ "$SCRIPT" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "permanent|pull access denied for x, repository does not exist" ]
  [[ ${lines[1]} == permanent\|* ]]
  [[ ${lines[2]} == ratelimit\|* ]]
  [ "${lines[3]}" = 'transient|Get "https://ghcr.io/v2/": net/http: TLS handshake timeout' ]
  [ "${lines[4]}" = "transient|timed out after 5s" ]
}

@test "json_str escapes quotes, backslashes and control characters" {
  run bash -c 'source "$1"; json_str "$(printf "a\"b\\\\c\nd\te\x01")"; printf "%s\n" "$REPLY"' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = '"a\"b\\c\nd\te"' ]
}

# ─── Command line ────────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ $output == *"Usage: pull-image.sh"* ]]
  [[ $output == *"--tui"* ]]
}

@test "usage errors exit 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ $output == *"unknown option: --bogus"* ]]
  run "$SCRIPT" --jobs 0
  [ "$status" -eq 2 ]
  run "$SCRIPT" --jobs=abc
  [ "$status" -eq 2 ]
  run "$SCRIPT" --color sometimes
  [ "$status" -eq 2 ]
  run "$SCRIPT" --root "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 2 ]
  run "$SCRIPT" stray-argument
  [ "$status" -eq 2 ]
}

@test "--tui refuses to run without a terminal" {
  run "$SCRIPT" --tui </dev/null
  [ "$status" -eq 2 ]
  [[ $output == *"needs an interactive terminal"* ]]
}

@test "an unreachable daemon exits 3" {
  touch "$FAKE_DOCKER_DIR/daemon-down"
  run "$SCRIPT" --dry-run
  [ "$status" -eq 3 ]
  [[ $output == *"cannot talk to the Docker daemon"* ]]
}

# ─── Discovery and planning ──────────────────────────────────────────────────

@test "dry run plans repo stacks only, dedupes references and never pulls" {
  standard_scenario
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Dry run: 2 image(s) to pull, 2 skipped, 0 excluded."* ]]
  [[ $output == *"nginx:latest"* ]]
  # "redis" and "docker.io/library/redis:latest" are one image, shown in its shortest form.
  [ "$(grep -c '· redis ' <<<"$output")" -eq 1 ]
  [[ $output != *"docker.io/library/redis:latest  "* ]]
  [[ $output == *"pinned by digest and already present"* ]]
  [[ $output == *"built locally (no registry digest)"* ]]
  [[ $output != *busybox* ]]
  [[ $output == *"ignored): other (1 container)"* ]]
  run grep -q '^pull ' "$FAKE_DOCKER_DIR/calls"
  [ "$status" -eq 1 ]
}

@test "Portainer-style paths match the repo by path suffix, nested dirs included" {
  standard_scenario
  run "$SCRIPT" --dry-run --project db
  [ "$status" -eq 0 ]
  [[ $output == *"Dry run: 1 image(s) to pull"* ]]
  [[ $output == *"redis"*"db"* ]]
}

@test "--all-projects also takes Compose stacks defined elsewhere" {
  standard_scenario
  run "$SCRIPT" --dry-run --all-projects
  [ "$status" -eq 0 ]
  [[ $output == *busybox:latest* ]]
}

@test "image and project filters, including the ignore file" {
  standard_scenario
  run "$SCRIPT" --dry-run --exclude 'redis*'
  [[ $output == *"Dry run: 1 image(s) to pull, 2 skipped, 1 excluded."* ]]

  run "$SCRIPT" --dry-run --include 'docker.io/library/nginx:*'
  [[ $output == *"Dry run: 1 image(s) to pull"* ]]
  [[ $output == *"nginx:latest"* ]]

  # The short form matches however the Compose file spells the reference.
  run "$SCRIPT" --dry-run --include 'redis:latest'
  [[ $output == *"Dry run: 1 image(s) to pull"* ]]

  run "$SCRIPT" --dry-run --skip-project web
  [[ $output == *"Dry run: 1 image(s) to pull, 1 skipped"* ]]

  printf '# comment\nproject:db\n  nginx:*  # trailing comment\n' >"$ROOT/.pull-image-ignore"
  run "$SCRIPT" --dry-run
  [[ $output == *"Dry run: 1 image(s) to pull, 2 skipped, 1 excluded."* ]]
  run "$SCRIPT" --dry-run --no-ignore-file
  [[ $output == *"Dry run: 2 image(s) to pull"* ]]
}

@test "--pull-local includes locally built images" {
  standard_scenario
  run "$SCRIPT" --dry-run --pull-local
  [[ $output == *"Dry run: 3 image(s) to pull, 1 skipped"* ]]
}

@test "outdated containers are reported with a redeploy hint" {
  standard_scenario
  tag nginx:latest sha256:nginx-2 # a newer image was pulled earlier, never deployed
  local_image "nginx|latest|sha256:dg-nginx2|sha256:nginx-2"
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Outdated containers (1)"* ]]
  [[ $output == *"web-app"*"nginx-1"*"nginx-2"* ]]
  [[ $output == *"docker compose -p web -f $ROOT/web/docker-compose.yml up -d"* ]]

  # ...and the report follows the image filters.
  run "$SCRIPT" --dry-run --exclude 'nginx:*'
  [[ $output != *"Outdated containers"* ]]
}

# ─── Pulling ─────────────────────────────────────────────────────────────────

@test "pulls each image once and tells updated from unchanged" {
  standard_scenario
  pulls nginx:latest new:sha256:nginx-2
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output == *"1 updated, 1 unchanged, 0 failed, 2 skipped."* ]]
  [[ $output == *"updated"*"nginx:latest"* ]]
  [[ $output == *"nginx-1 → nginx-2"* || $output == *"nginx-1 -> nginx-2"* ]]
  [ "$(pull_count nginx:latest)" -eq 1 ]
  [ "$(pull_count redis)" -eq 1 ]
  [ "$(grep -c '^pull ' "$FAKE_DOCKER_DIR/calls")" -eq 2 ]
  # The new image makes web-app outdated.
  [[ $output == *"Outdated containers (1)"* ]]
}

@test "a Portainer stack gets a Portainer hint" {
  standard_scenario
  pulls redis new:sha256:redis-2
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output == *"Outdated containers (2)"* ]]
  [[ $output == *"db  (_FORMAL/db/compose.yaml)"* ]]
  [[ $output == *"deployed by Portainer"* ]]
}

@test "a permanent failure is not retried, exits 1 and keeps its log" {
  standard_scenario
  pulls redis denied
  run "$SCRIPT" --retries 3
  [ "$status" -eq 1 ]
  [ "$(pull_count redis)" -eq 1 ]
  [[ $output == *"Failed (1):"* ]]
  [[ $output == *"pull access denied for redis"* ]]
  log=$(sed -n 's/^ *log: //p' <<<"$output")
  [ -f "$log" ]
  grep -q 'giving up' "$log"
}

@test "transient failures are retried with backoff" {
  standard_scenario
  pulls redis flaky:2
  run "$SCRIPT" --retries 2
  [ "$status" -eq 0 ]
  [ "$(pull_count redis)" -eq 3 ]
  [[ $output == *"(attempt 3)"* ]]
}

@test "retries are bounded" {
  standard_scenario
  pulls redis flaky:5
  run "$SCRIPT" --retries 1
  [ "$status" -eq 1 ]
  [ "$(pull_count redis)" -eq 2 ]
  [[ $output == *"TLS handshake timeout"* ]]
}

@test "a hung pull is stopped by --timeout" {
  command -v timeout >/dev/null || skip 'timeout(1) not available'
  standard_scenario
  pulls redis hang
  SECONDS=0
  run "$SCRIPT" --timeout 1 --retries 0
  [ "$status" -eq 1 ]
  [[ $output == *"timed out after 1s"* ]]
  [ "$SECONDS" -lt 10 ]
}

@test "--json writes a machine-readable report to stdout" {
  command -v jq >/dev/null || skip 'jq not available'
  standard_scenario
  pulls nginx:latest new:sha256:nginx-2
  run --separate-stderr "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary | "\(.updated) \(.unchanged) \(.skipped) \(.outdated_containers)"' <<<"$output")" = "1 1 2 1" ]
  [ "$(jq -r '.images[] | select(.ref == "nginx:latest") | .new_id' <<<"$output")" = sha256:nginx-2 ]
  [ "$(jq -r '.outdated_containers[0].name' <<<"$output")" = web-app ]
  [[ $stderr == *"Finished in"* ]]
}

@test "--json on a dry run marks planned images" {
  command -v jq >/dev/null || skip 'jq not available'
  standard_scenario
  run --separate-stderr "$SCRIPT" --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.images[] | select(.status == "planned")] | length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.dry_run' <<<"$output")" = true ]
}

@test "a second concurrent run is refused with exit 3" {
  command -v flock >/dev/null || skip 'flock(1) not available'
  standard_scenario
  exec 9>>"$PULL_IMAGE_LOCK"
  flock -n 9
  run "$SCRIPT"
  exec 9>&-
  [ "$status" -eq 3 ]
  [[ $output == *"another pull-image.sh run is in progress"* ]]
}

@test "SIGTERM stops running pulls and exits 130" {
  standard_scenario
  pulls redis hang
  "$SCRIPT" >"$BATS_TEST_TMPDIR/out" 2>&1 &
  pid=$!
  for _ in $(seq 50); do
    grep -q '^pull redis$' "$FAKE_DOCKER_DIR/calls" 2>/dev/null && break
    sleep 0.1
  done
  sleep 0.3
  kill -TERM "$pid"
  status=0
  wait "$pid" || status=$?
  [ "$status" -eq 130 ]
  grep -q 'cancelled' "$BATS_TEST_TMPDIR/out"
  sleep 0.5
  run pgrep -fx 'sleep 300' # the hung pull must not outlive the script
  [ "$status" -eq 1 ]
}

@test "no matching containers is not an error" {
  container "stranger|busybox:latest|sha256:bb-1|other|x|/opt/other|/opt/other/docker-compose.yml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output == *"No Compose containers matched"* ]]
}

# ─── TUI ─────────────────────────────────────────────────────────────────────

@test "TUI: select all, pull, quit from the results screen" {
  command -v script >/dev/null || skip 'script(1) not available'
  standard_scenario
  pulls nginx:latest new:sha256:nginx-2
  run bash -c '{ sleep 1; printf "\r"; sleep 3; printf q; sleep 1; } |
    script -qefc "$1 --tui" /dev/null' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output == *"choose images to pull"* ]]
  [[ $output == *"1 updated, 1 unchanged, 0 failed, 2 skipped."* ]]
  [ "$(grep -c '^pull ' "$FAKE_DOCKER_DIR/calls")" -eq 2 ]
}

@test "TUI: quitting the selection pulls nothing" {
  command -v script >/dev/null || skip 'script(1) not available'
  standard_scenario
  run bash -c '{ sleep 1; printf q; sleep 1; } | script -qefc "$1 --tui" /dev/null' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output == *"Nothing was pulled."* ]]
  run grep -q '^pull ' "$FAKE_DOCKER_DIR/calls"
  [ "$status" -eq 1 ]
}
