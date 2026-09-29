# CommunityOS — Capstone demo script (≈7 minutes)

## 1. The problem (45 s)
- Fun Circle knows families as scattered transactions: waivers and payments in Square, party requests and bookings in Salesforce, emails in Gmail, and context in staff notes.
- A parent calls: "Can we book again?" Staff can't see the family's history in one place, re-ask questions, and miss upsells.
- Nobody notices that families whose party anniversary is coming up haven't rebooked (116 candidate parties in the next 30 days in our data).

## 2. The solution in one line (15 s)
One household view in Salesforce plus an AI assistant that reads the family's history and suggests the next staff action. Humans approve every task; customers never see AI output.

## 3. Live demo (3 min)
1. **Family 360 tab** → search by phone → household opens: people, parties, Square orders, camps, staff notes, open tasks.
2. **Get insights** → Claude summarizes the family and suggests tasks, each citing a date or record (e.g. "Booking 1 party is 2026-11-28; family still deciding on face painting").
3. **Create task** on one suggestion → appears under Open tasks with an **AI** badge and its reason.
4. **Add a staff note** → saved to the existing Team notes object.
5. **AI Call Logs tab** → open the newest log: context sent is tokens only (Person A, Booking 1), no names, emails, phones or health notes; model, prompt version, latency, tasks suggested vs created.
6. **Nightly job**: rules-only rebooking reminders 45 days before a party anniversary (no AI needed where rules are exact).

## 4. How AI concepts from the course are applied (1.5 min)
| Concept | Where |
|---|---|
| Context engineering | FamilyContextBuilder: allowlisted fields only, tokenized, capped at 20 rows per source |
| Prompt design + versioning | FamilyInsightPrompt v3: role, grounding rules, business glossary (FP, BA), JSON contract |
| Structured output | Strict JSON schema, parsed and validated in Apex |
| Guardrails | Redactor (names, contact details, IDs, health sentences); output blocked if it contains contact details; tasks citing unknown records dropped; max 3 tasks; due date clamped |
| Human in the loop | AI suggests, staff click to create; no customer-facing messages |
| Provider abstraction | LlmClient interface: mock and Claude, switched by a setting |
| Observability | AI_Call_Log__c for every call, with fields sent and a Tasks Created counter |
| Evaluation | eval-run.apex on 27 real households: PII leaks, validity, usefulness, guardrail drops, latency (mock vs Claude) |
| Deterministic vs probabilistic | Nightly reminders are rules; judgement over free-text notes is AI |

## 5. Results and learnings (1 min)
- See docs/eval-results.md: mock vs Claude on the same 27 households.
- Learning 1: Claude's built-in reasoning consumed the 1,024-token budget and cut answers short; fixed by raising the limit and detecting `stop_reason = max_tokens`.
- Learning 2: the model guessed "BA = Bounce Activity"; a shorthand glossary in the prompt fixed it (prompt v1 → v2).
- Learning 3: one suggestion offered a discount that isn't Fun Circle policy; prompt v3 forbids promising discounts, prices or policies not in the data.
- Result: Claude found a useful next step for 27/27 households vs 17/27 for the rules baseline, with 0 privacy leaks.

## 6. What's next (30 s)
- Pilot with front-desk staff for two weeks; measure tasks created vs suggested and bookings from AI tasks.
- Gmail and Square history flowing in automatically; Care Card fields moved to encrypted fields.
- Tenant #2: another family venue on the same package.
