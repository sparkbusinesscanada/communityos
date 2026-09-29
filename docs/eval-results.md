# CommunityOS — Eval results

Script: `scripts/apex/eval-run.apex` (run in batches of 3 households; see header of the script).
Sample: the 27 most recently modified COS households with a booking in the last 540 days.

| Metric | What it measures | Target | mock-rules-v1 (29 Sep 2026) | Claude (pending API key) |
|---|---|---|---|---|
| PII leaks | Any contact / minor name, email, phone or care card found in the context sent to the AI | 0 | **0** | |
| Valid output | Response parsed into the agreed JSON schema | 100% | **27/27** | |
| Useful output | Households that got at least one insight or suggested task | higher is better | **17/27** | |
| Tasks suggested | Total suggested staff tasks | — | 17 | |
| Dropped by guardrails | Tasks pointing at invented records or over the 3-task cap | low, never silent | 0 | |
| Avg latency | Time in the LLM step | < 10 s | 2 ms | |

## Known gaps the real model should close

- Rules miss intent buried in staff notes, e.g. "asked about face painting and balloon art prices, will call back" on a booked party. Expected Claude task: follow up on the add-on before the party date.
- Staff names and initials (e.g. "RR", "DP") in notes are not masked; they are staff, not customers.

## How to rerun

```
cd ~/code/communityos
for off in 0 3 6 9 12 15 18 21 24; do sed "s/Integer offsetRows = 0;/Integer offsetRows = $off;/" scripts/apex/eval-run.apex > /tmp/eval-$off.apex; sf apex run --target-org cos --file /tmp/eval-$off.apex | grep -o "EVAL>> .*"; done
```
