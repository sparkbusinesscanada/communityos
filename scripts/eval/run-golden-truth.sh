#!/bin/bash
ACCS=($(tail -1 .local/eval-accounts.txt))
: > .local/eval/truth.jsonl
for i in 0 2 4 6; do
  L="'${ACCS[$i]}','${ACCS[$((i+1))]}'"
  sed "s/__ACCS__/$L/" scripts/eval/golden-truth.apex.tmpl > .local/eval/truth.apex
  sf apex run -o cos -f .local/eval/truth.apex 2>&1 | grep -o 'TRUTH \[.*' | tail -1 | sed 's/^TRUTH //' >> .local/eval/truth.jsonl
done
echo DONE >> .local/eval/truth.done
