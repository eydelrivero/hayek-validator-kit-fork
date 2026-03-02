#!/bin/bash
set -euo pipefail

if [ -d "/hayek-validator-kit" ]; then
  REPO_ROOT="/hayek-validator-kit"
else
  REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

HVK_TEST="$REPO_ROOT/test-harness/bin/hvk-test"

if [ ! -x "$HVK_TEST" ]; then
  echo "❌ hvk-test not found or not executable at $HVK_TEST"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required for harness contract checks"
  exit 1
fi

echo "🔎 Checking harness contract surface..."

LIST_JSON="$("$HVK_TEST" list --json)"
echo "$LIST_JSON" | jq '.'

for target in compose vm latitude; do
  echo "▶ describe target=$target"
  "$HVK_TEST" describe --target "$target" --scenario agave_only --json | jq '.'
done

echo "✅ Harness contract checks passed."
