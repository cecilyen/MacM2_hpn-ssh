#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APPLY=0
KEEP_LATEST=2
CLEAN_LOGS=0
CLEAN_PROFILES=0
CLEAN_ALL=0
READ_LINES_RESULT=()

usage() {
  cat <<'USAGE'
Usage: scripts/clean-generated-artifacts.sh [options]

Safely clean generated MacHPNSSH artifacts. The default mode is a dry run that
prunes old build runs and validation directories while keeping the newest two
runs per variant.

Options:
  --apply             Delete files instead of printing what would be removed.
  --keep-latest N     Keep newest N build runs per variant. Default: 2.
  --logs              Also prune logs with the same keep count.
  --profiles          Also remove generated profile data.
  --all               Remove all known generated directories.
  -h, --help          Show this help.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --keep-latest)
      [[ $# -ge 2 ]] || die "--keep-latest requires a value"
      KEEP_LATEST="$2"
      [[ "$KEEP_LATEST" =~ ^[0-9]+$ ]] || die "--keep-latest must be numeric"
      shift 2
      ;;
    --logs)
      CLEAN_LOGS=1
      shift
      ;;
    --profiles)
      CLEAN_PROFILES=1
      shift
      ;;
    --all)
      CLEAN_ALL=1
      CLEAN_LOGS=1
      CLEAN_PROFILES=1
      KEEP_LATEST=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_workspace_path() {
  local path="$1"
  case "$path" in
    "$ROOT_DIR"/*) ;;
    *) die "Refusing to remove path outside workspace: $path" ;;
  esac
}

remove_path() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  require_workspace_path "$path"

  if [[ "$APPLY" -eq 1 ]]; then
    printf 'remove: %s\n' "$path"
    rm -rf -- "$path"
  else
    printf 'would remove: %s\n' "$path"
  fi
}

prune_read_lines_newest_first() {
  local keep="$1"
  if ((${#READ_LINES_RESULT[@]} == 0)); then
    return 0
  fi

  local index=0
  local path
  for path in "${READ_LINES_RESULT[@]}"; do
    index=$((index + 1))
    if [[ "$index" -gt "$keep" ]]; then
      remove_path "$path"
    fi
  done
}

remove_read_lines() {
  if ((${#READ_LINES_RESULT[@]} == 0)); then
    return 0
  fi

  local path
  for path in "${READ_LINES_RESULT[@]}"; do
    remove_path "$path"
  done
}

collect_sorted_dirs() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -type d -print | sort -r
}

collect_sorted_files() {
  local dir="$1"
  local pattern="$2"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -type f -name "$pattern" -print | sort -r
}

prune_known_logs() {
  local pattern
  for pattern in \
    'hpnssh-build-*.log' \
    'hpnssh-awslc-build-*.log' \
    'hpnssh-awslc-zlibng-build-*.log'; do
    read_lines collect_sorted_files "${ROOT_DIR}/logs" "$pattern"
    prune_read_lines_newest_first "$KEEP_LATEST"
  done
}

read_lines() {
  local line
  READ_LINES_RESULT=()
  while IFS= read -r line; do
    READ_LINES_RESULT+=("$line")
  done < <("$@")
}

main() {
  local workdir
  for workdir in build build-awslc build-awslc-zlibng; do
    local abs_workdir="${ROOT_DIR}/${workdir}"

    if [[ "$CLEAN_ALL" -eq 1 ]]; then
      remove_path "$abs_workdir"
      continue
    fi

    local runs_dir="${abs_workdir}/runs"
    if [[ -d "$runs_dir" ]]; then
      read_lines collect_sorted_dirs "$runs_dir"
      prune_read_lines_newest_first "$KEEP_LATEST"
    fi

    if [[ -d "$abs_workdir" ]]; then
      read_lines find "$abs_workdir" -mindepth 1 -maxdepth 1 -type d -name 'validation.*' -print
      remove_read_lines
    fi
  done

  if [[ "$CLEAN_LOGS" -eq 1 ]]; then
    if [[ "$CLEAN_ALL" -eq 1 ]]; then
      remove_path "${ROOT_DIR}/logs"
    else
      prune_known_logs
    fi
  fi

  if [[ "$CLEAN_PROFILES" -eq 1 ]]; then
    remove_path "${ROOT_DIR}/profiles"
  fi

  if [[ "$APPLY" -eq 0 ]]; then
    printf 'dry run only; pass --apply to delete listed paths\n'
  fi
}

main "$@"
