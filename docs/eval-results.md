# CommunityOS — Eval results

Script: `scripts/apex/eval-run.apex` (run in batches of 3 households; see header of the script).
Sample: the 27 most recently modified COS households with a booking in the last 540 days.

| Metric | What it measures | Target | mock-rules-v1 (29 Sep 2026) | claude-sonnet-5, prompt v2 (29 Sep 2026) |
|---|---|---|---|---|
| PII leaks | Any contact / minor name, email, phone or care card found in the context sent to the AI | 0 | **0** | **0** |
| Valid output | Response parsed into the agreed JSON schema | 100% | **27/27** | **27/27** |
| Useful output | Households that got at least one insight or suggested task | higher is better | **17/27** | **27/27** |
| Tasks suggested | Total suggested staff tasks | — | 17 | 58 |
| Dropped by guardrails | Tasks pointing at invented records or over the 3-task cap | low, never silent | 0 | 0 |
| Avg latency | Time in the LLM step | < 10 s | 2 ms | ~6.6 s |

## What Claude added over the rules baseline

Sample suggested tasks (subjects as generated):
- Offer FP add-on for Booking 1
- Call to confirm final party details for Booking 1
- Follow up on open 25-kid Birthday Party enquiry
- Collect payment for Order 2 laser tag package
- Review and close out Order 1 draft invoice

Rules found 17 suggestions in 17 households; Claude found 58 in all 27, mostly from staff notes and invoice status the rules never read.

## Issues found and fixed during the Claude run

- Prompt v1 + 1,024 max tokens: the model's built-in reasoning used 555 tokens and the JSON was cut off. Fix: 4,096 tokens and an explicit `stop_reason = max_tokens` error.
- Prompt v1 guessed "BA = Bounce Activity". Fix: staff shorthand glossary in prompt v2.

## Open quality issues (prompt v3 candidates)

- One suggestion offered a "rebooking/anniversary discount", which is not a Fun Circle policy. Fixed in prompt v3: never promise discounts, prices or policies not in the data (rerun eval to confirm).
- Staff names and initials in notes are not masked (staff, not customers).

## Known gaps the rules baseline could not close

- Rules miss intent buried in staff notes, e.g. "asked about face painting and balloon art prices, will call back" on a booked party. Expected Claude task: follow up on the add-on before the party date.
- Staff names and initials (e.g. "RR", "DP") in notes are not masked; they are staff, not customers.

## How to rerun

```
cd ~/code/communityos
for off in 0 3 6 9 12 15 18 21 24; do sed "s/Integer offsetRows = 0;/Integer offsetRows = $off;/" scripts/apex/eval-run.apex > /tmp/eval-$off.apex; sf apex run --target-org cos --file /tmp/eval-$off.apex | grep -o "EVAL>> .*"; done
```
