#!/bin/bash
set -u
MODE="$1"
OUT=".local/eval/$MODE"
mkdir -p "$OUT"
for ACC in $(cat .local/eval-accounts.txt | tail -1); do
  for CALL in A B C; do
    sed "s/__ACC__/$ACC/; s/__CALL__/$CALL/" scripts/eval/golden-desk.apex.tmpl > "$OUT/run.apex"
    sf apex run -o cos -f "$OUT/run.apex" 2>&1 | grep -o 'EVALJSON .*' | sed 's/^EVALJSON //' > "$OUT/$ACC-$CALL.json"
  done
done
echo DONE > "$OUT/DONE"
