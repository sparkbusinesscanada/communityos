#!/usr/bin/env bash
set -euo pipefail

ORG="${1:-funcircle}"
MODE="${2:-dry-run}"
shift $(( $# > 2 ? 2 : $# ))
DIRS=("$@")
if [ ${#DIRS[@]} -eq 0 ]; then
  DIRS=("force-app")
fi

ARGS=()
for d in "${DIRS[@]}"; do
  ARGS+=(--source-dir "$d")
done

if [ "$MODE" = "dry-run" ]; then
  sf project deploy start "${ARGS[@]}" --target-org "$ORG" --test-level NoTestRun --dry-run --wait 30
else
  sf project deploy start "${ARGS[@]}" --target-org "$ORG" --test-level NoTestRun --wait 30
fi
