#!/usr/bin/env bash

set -uo pipefail

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly CONFIG_FILES_LABEL='com.docker.compose.project.config_files'
readonly WORKING_DIR_LABEL='com.docker.compose.project.working_dir'

dry_run=false

usage() {
  cat <<'EOF'
Usage: ./pull-image.sh [--dry-run]

Pull each unique image used by a running Docker Compose container whose
Compose definition exists under this script's directory.

Options:
  -n, --dry-run  List the images without pulling them
  -h, --help     Show this help
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    -n|--dry-run)
      dry_run=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

command -v docker >/dev/null 2>&1 || die 'docker is not installed or not in PATH'
docker info >/dev/null 2>&1 || die 'cannot connect to the Docker daemon'

shopt -s globstar nullglob
compose_files=(
  "$SCRIPT_DIR"/**/compose.yml
  "$SCRIPT_DIR"/**/compose.yaml
  "$SCRIPT_DIR"/**/docker-compose.yml
  "$SCRIPT_DIR"/**/docker-compose.yaml
)

((${#compose_files[@]} > 0)) || die "no Compose files found under $SCRIPT_DIR"

declare -A local_compose_keys=()
for compose_file in "${compose_files[@]}"; do
  compose_parent="$(basename -- "$(dirname -- "$compose_file")")"
  compose_name="$(basename -- "$compose_file")"
  local_compose_keys["$compose_parent|$compose_name"]=1
done

mapfile -t running_container_ids < <(docker ps --quiet)
if ((${#running_container_ids[@]} == 0)); then
  printf 'No running containers found.\n'
  exit 0
fi

declare -A images=()
while IFS=$'\t' read -r image config_files working_dir; do
  [[ -n "$image" && -n "$config_files" && -n "$working_dir" ]] || continue

  managed=false
  IFS=',' read -ra container_compose_files <<<"$config_files"
  for config_file in "${container_compose_files[@]}"; do
    if [[ "$config_file" == "$SCRIPT_DIR/"* && -f "$config_file" ]]; then
      managed=true
      break
    fi

    compose_key="$(basename -- "$working_dir")|$(basename -- "$config_file")"
    if [[ -n "${local_compose_keys[$compose_key]+present}" ]]; then
      managed=true
      break
    fi
  done

  if [[ "$managed" == true ]]; then
    images["$image"]=1
  fi
done < <(
  docker inspect \
    --format '{{.Config.Image}}{{printf "\t"}}{{index .Config.Labels "'"$CONFIG_FILES_LABEL"'"}}{{printf "\t"}}{{index .Config.Labels "'"$WORKING_DIR_LABEL"'"}}' \
    "${running_container_ids[@]}"
)

if ((${#images[@]} == 0)); then
  printf 'No running Compose containers matched definitions under %s.\n' "$SCRIPT_DIR"
  exit 0
fi

mapfile -t sorted_images < <(printf '%s\n' "${!images[@]}" | LC_ALL=C sort)
printf 'Found %d unique image(s) used by matching running containers.\n' "${#sorted_images[@]}"

if [[ "$dry_run" == true ]]; then
  printf 'Dry run; images that would be pulled:\n'
  printf '  %s\n' "${sorted_images[@]}"
  exit 0
fi

failures=0
for image in "${sorted_images[@]}"; do
  printf '\nPulling %s\n' "$image"
  if ! docker pull "$image"; then
    printf 'Failed to pull %s\n' "$image" >&2
    ((failures += 1))
  fi
done

if ((failures > 0)); then
  die "$failures image pull(s) failed"
fi

printf '\nSuccessfully pulled all %d image(s).\n' "${#sorted_images[@]}"
