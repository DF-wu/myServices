#!/bin/sh
set -eu

# Unit-test the read-only consumer gate with a fake Docker CLI. No real Docker
# object is changed or queried by this test.

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
subject=$repo_root/scripts/validate-consumer-runtime.sh
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

mkdir -p "$workdir/bin"
cat >"$workdir/bin/docker" <<'EOF'
#!/bin/sh
set -eu
name=$4
case ${FAKE_DOCKER_CASE:-unsafe}:$name in
  safe:safe-consumer)
    printf '%s\n' '[{"Id":"consumer-id","HostConfig":{"Privileged":false,"CapDrop":["ALL"],"CapAdd":[],"SecurityOpt":["no-new-privileges:true"],"PidMode":"","NetworkMode":"bridge"},"State":{"Running":false,"Pid":0}}]'
    ;;
  unsafe:unsafe-consumer)
    printf '%s\n' '[{"Id":"consumer-id","HostConfig":{"Privileged":false,"CapDrop":[],"CapAdd":[],"SecurityOpt":[],"PidMode":"","NetworkMode":"bridge"},"State":{"Running":false,"Pid":0}}]'
    ;;
  *) exit 1 ;;
esac
EOF
chmod 700 "$workdir/bin/docker"

if PATH="$workdir/bin:$PATH" FAKE_DOCKER_CASE=unsafe \
  sh "$subject" unsafe-consumer >/dev/null 2>&1; then
  fail 'unsafe consumer configuration was accepted'
fi
printf 'ok - unsafe consumer capability configuration is rejected\n'

if PATH="$workdir/bin:$PATH" FAKE_DOCKER_CASE=safe \
  sh "$subject" safe-consumer >/dev/null 2>&1; then
  :
else
  fail 'safe stopped consumer configuration was rejected'
fi
printf 'ok - safe stopped consumer configuration is accepted\n'

if PATH="$workdir/bin:$PATH" FAKE_DOCKER_CASE=missing \
  sh "$subject" missing-consumer >/dev/null 2>&1; then
  fail 'missing consumer was accepted'
fi
printf 'ok - missing consumer is rejected\n'

printf 'Consumer safety tests passed.\n'
