#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK_ROOT="${WORK_ROOT:-$REPO_ROOT/test-harness/work}"
KEEP_RUNS="${KEEP_RUNS:-6}"
MIN_FREE_GB="${MIN_FREE_GB:-40}"
DRY_RUN=false
PRUNE_MUTABLE_CACHE_DIRS=false
PRUNE_IMMUTABLE_CACHE_DIRS="${PRUNE_IMMUTABLE_CACHE_DIRS:-true}"
IMMUTABLE_CACHE_ROOT="${IMMUTABLE_CACHE_ROOT:-$WORK_ROOT/_vm-immutable-cache}"
KEEP_ENTRYPOINT_IMMUTABLE_CACHES="${KEEP_ENTRYPOINT_IMMUTABLE_CACHES:-3}"
KEEP_PREPARED_IMMUTABLE_CACHES="${KEEP_PREPARED_IMMUTABLE_CACHES:-3}"

usage() {
  cat <<'EOF'
Usage:
  prune-vm-test-runs.sh [options]

Options:
  --work-root <path>         (default: ./test-harness/work)
  --keep-runs <n>            Keep newest N runs per suite root (default: 6)
  --min-free-gb <n>          Keep pruning oldest runs until free space >= N GB (default: 40)
  --dry-run                  Show what would be removed without deleting
  --prune-mutable-cache-dirs Remove mutable/legacy cache dirs (_shared-entrypoint-vm, _prepared-vms)
  --prune-immutable-caches   Prune immutable caches under _vm-immutable-cache (default: enabled)
  --no-prune-immutable-caches
  --keep-entrypoint-caches <n> Keep newest N immutable entrypoint caches (default: 3)
  --keep-prepared-caches <n>   Keep newest N immutable prepared-vm caches (default: 3)
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
    --prune-mutable-cache-dirs)
      PRUNE_MUTABLE_CACHE_DIRS=true
      shift
      ;;
    --prune-immutable-caches)
      PRUNE_IMMUTABLE_CACHE_DIRS=true
      shift
      ;;
    --no-prune-immutable-caches)
      PRUNE_IMMUTABLE_CACHE_DIRS=false
      shift
      ;;
    --keep-entrypoint-caches)
      KEEP_ENTRYPOINT_IMMUTABLE_CACHES="${2:-}"
      shift 2
      ;;
    --keep-prepared-caches)
      KEEP_PREPARED_IMMUTABLE_CACHES="${2:-}"
      shift 2
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
if ! [[ "$KEEP_ENTRYPOINT_IMMUTABLE_CACHES" =~ ^[0-9]+$ ]]; then
  echo "--keep-entrypoint-caches must be a non-negative integer (got: $KEEP_ENTRYPOINT_IMMUTABLE_CACHES)" >&2
  exit 2
fi
if ! [[ "$KEEP_PREPARED_IMMUTABLE_CACHES" =~ ^[0-9]+$ ]]; then
  echo "--keep-prepared-caches must be a non-negative integer (got: $KEEP_PREPARED_IMMUTABLE_CACHES)" >&2
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

list_dirs_desc() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
    | sort -nr \
    | awk '{ $1=""; sub(/^ /, ""); print }'
}

list_dirs_asc() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
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

prune_mutable_cache_dirs_for_root() {
  local root="$1"
  local dir
  [[ -d "$root" ]] || return 0
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    remove_dir "$dir"
  done < <(
    find "$root" -mindepth 1 -maxdepth 1 -type d \
      \( -name "_shared-entrypoint-vm" -o -name "_prepared-vms" \) \
      -printf '%T@ %p\n' \
      | sort -n \
      | awk '{ $1=""; sub(/^ /, ""); print }'
  )
}

prune_empty_dirs_under_root() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    remove_dir "$dir"
  done < <(
    find "$root" -mindepth 1 -type d -empty -printf '%T@ %p\n' \
      | sort -n \
      | awk '{ $1=""; sub(/^ /, ""); print }'
  )
}

prune_by_count_for_cache_root() {
  local root="$1"
  local keep="$2"
  mapfile -t dirs < <(list_dirs_desc "$root")
  local idx=0
  for dir in "${dirs[@]}"; do
    if ((idx >= keep)); then
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

oldest_dir_across_immutable_roots() {
  local oldest=""
  local oldest_ts=""
  local root=""
  local candidate=""
  local ts=""
  local line=""

  for root in "${IMMUTABLE_PRUNE_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    line="$(find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -n | head -n1 || true)"
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

IMMUTABLE_PRUNE_ROOTS=(
  "$IMMUTABLE_CACHE_ROOT/entrypoint-vm-cli"
  "$IMMUTABLE_CACHE_ROOT/prepared-vms"
)

for root in "${SUITE_ROOTS[@]}"; do
  prune_by_count_for_root "$root"
done

if [[ "$PRUNE_MUTABLE_CACHE_DIRS" == true ]]; then
  for root in "${SUITE_ROOTS[@]}"; do
    prune_mutable_cache_dirs_for_root "$root"
  done
fi

if [[ "$PRUNE_IMMUTABLE_CACHE_DIRS" == true ]]; then
  prune_empty_dirs_under_root "$IMMUTABLE_CACHE_ROOT"
  prune_by_count_for_cache_root "$IMMUTABLE_CACHE_ROOT/entrypoint-vm-cli" "$KEEP_ENTRYPOINT_IMMUTABLE_CACHES"
  prune_by_count_for_cache_root "$IMMUTABLE_CACHE_ROOT/prepared-vms" "$KEEP_PREPARED_IMMUTABLE_CACHES"
  prune_empty_dirs_under_root "$IMMUTABLE_CACHE_ROOT"
fi

if ((MIN_FREE_GB > 0)); then
  free_gb="$(get_free_gb "$WORK_ROOT")"
  while ((free_gb < MIN_FREE_GB)); do
    oldest="$(oldest_dir_across_roots)"
    if [[ -z "$oldest" ]]; then
      if [[ "$PRUNE_IMMUTABLE_CACHE_DIRS" == true ]]; then
        oldest="$(oldest_dir_across_immutable_roots)"
      fi
      [[ -n "$oldest" ]] || break
    fi
    remove_dir "$oldest"
    free_gb="$(get_free_gb "$WORK_ROOT")"
  done
  echo "[prune] free space: ${free_gb}G (target: ${MIN_FREE_GB}G)" >&2
fi
