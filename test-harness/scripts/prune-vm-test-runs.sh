#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK_ROOT="${WORK_ROOT:-$REPO_ROOT/test-harness/work}"
KEEP_RUNS="${KEEP_RUNS:-6}"
MIN_FREE_GB="${MIN_FREE_GB:-40}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  prune-vm-test-runs.sh [options]

Options:
  --work-root <path>         (default: ./test-harness/work)
  --keep-runs <n>            Keep newest N runs per suite root (default: 6)
  --min-free-gb <n>          Keep pruning oldest runs until free space >= N GB (default: 40)
  --dry-run                  Show what would be removed without deleting
EOF
}

while (($# > 0)); do
  case "$1" in
    --work-root)
      WORK_ROOT="${2:-}"
      shift 2
      ;;
    --keep-runs)
      KEEP_RUNS="${2:-}"
      shift 2
      ;;
    --min-free-gb)
      MIN_FREE_GB="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if ! [[ "$KEEP_RUNS" =~ ^[0-9]+$ ]]; then
  echo "--keep-runs must be a non-negative integer (got: $KEEP_RUNS)" >&2
  exit 2
fi
if ! [[ "$MIN_FREE_GB" =~ ^[0-9]+$ ]]; then
  echo "--min-free-gb must be a non-negative integer (got: $MIN_FREE_GB)" >&2
  exit 2
fi

remove_dir() {
  local dir="$1"
  if [[ "$DRY_RUN" == true ]]; then
    echo "[prune] dry-run remove: $dir" >&2
    return 0
  fi
  rm -rf -- "$dir"
  echo "[prune] removed: $dir" >&2
}

list_run_dirs_desc() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d ! -name logs ! -name '_*' -printf '%T@ %p\n' \
    | sort -nr \
    | awk '{ $1=""; sub(/^ /, ""); print }'
}

list_run_dirs_asc() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d ! -name logs ! -name '_*' -printf '%T@ %p\n' \
    | sort -n \
    | awk '{ $1=""; sub(/^ /, ""); print }'
}

get_free_gb() {
  local path="$1"
  df -BG "$path" | awk 'NR==2 { gsub(/G/, "", $4); print $4 }'
}

prune_by_count_for_root() {
  local root="$1"
  mapfile -t dirs < <(list_run_dirs_desc "$root")
  local idx=0
  for dir in "${dirs[@]}"; do
    if ((idx >= KEEP_RUNS)); then
      remove_dir "$dir"
    fi
    idx=$((idx + 1))
  done
}

oldest_dir_across_roots() {
  local oldest=""
  local oldest_ts=""
  local root=""
  local candidate=""
  local ts=""
  local line=""

  for root in "${SUITE_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    line="$(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name logs ! -name '_*' -printf '%T@ %p\n' | sort -n | head -n1 || true)"
    [[ -n "$line" ]] || continue
    ts="${line%% *}"
    candidate="${line#* }"
    if [[ -z "$oldest" ]]; then
      oldest="$candidate"
      oldest_ts="$ts"
      continue
    fi
    if awk "BEGIN {exit !($ts < $oldest_ts)}"; then
      oldest="$candidate"
      oldest_ts="$ts"
    fi
  done

  printf '%s\n' "$oldest"
}

SUITE_ROOTS=(
  "$WORK_ROOT/vm-hot-swap"
  "$WORK_ROOT/vm-hot-swap-l2"
  "$WORK_ROOT/vm-hot-swap-l3"
)

for root in "${SUITE_ROOTS[@]}"; do
  prune_by_count_for_root "$root"
done

if ((MIN_FREE_GB > 0)); then
  free_gb="$(get_free_gb "$WORK_ROOT")"
  while ((free_gb < MIN_FREE_GB)); do
    oldest="$(oldest_dir_across_roots)"
    if [[ -z "$oldest" ]]; then
      break
    fi
    remove_dir "$oldest"
    free_gb="$(get_free_gb "$WORK_ROOT")"
  done
  echo "[prune] free space: ${free_gb}G (target: ${MIN_FREE_GB}G)" >&2
fi
