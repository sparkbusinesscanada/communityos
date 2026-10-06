# CommunityOS

**Family 360 for owner-run family venues.** One view of every household, with Claude helping part-time desk staff recognise families and bring them back.

Built as a 100xEngineers Cohort 7 capstone and running in production at [Fun Circle](https://funcircle.ca), an indoor playground and party venue in Surrey, BC.

## The problem

Birthday-party families come once and rarely return. Only **7%** of Fun Circle's 2024 party families (51 of 733) booked another party in 2025. Parties live in Salesforce, walk-in visits live in Square, and the person at the desk often doesn't know the family in front of them.

## What's in production

| Piece | What it does | Where in the repo |
| --- | --- | --- |
| Households | Groups contacts into one family account by phone number (12,583 households) | `ContactHousehold.trigger`, `ContactHouseholdService`, `ContactHouseholdBatch` |
| Visits | Loads Square walk-in orders nightly at 2:30 am and links them to the household (9,114 visits) | `Visit__c`, `SquareVisitSync`, `SquareVisitSyncJob` |
| Family 360 | Search by phone or name (Contacts, Accounts and open Leads) and see parties, visits, notes and balances | `lwc/family360`, `Family360Controller`, `VisitSummaryService` |
| Ask | Staff ask a plain question about a family; Claude answers and cites the records it used | `DeskAgentService`, `DeskAnswerPrompt` |
| AI Insights | Up to three suggested next steps; nothing happens until staff confirm | `FamilyInsightService`, `FamilyInsightPrompt` |
| Usage banner | Today's AI calls, tokens and the month's spend against budget | `AiGuard`, `AI_Call_Log__c` |
| Owner daily brief | 7:00 am email: today's parties, the next 7 days, unpaid orders, yesterday's visits | `OwnerBriefApi` (Apex REST) + [`n8n/owner-daily-brief.json`](n8n/owner-daily-brief.json) |

## How the LLM is used

Each Ask or AI Insights request makes **one** call to Claude, wrapped on both sides by plain Apex:

```
1 Gather  ->  2 Mask  ->  3 Claude  ->  4 Check  ->  5 Confirm
 Apex         Apex        Anthropic     Apex         staff
                          API
```

1. **Gather**: `FamilyContextBuilder` reads the household's parties, visits, notes and balances.
2. **Mask**: `Redactor` swaps names for tokens and strips phones and emails. Children's details, birthdays and allergy flags are never sent.
3. **Claude**: `ClaudeLlmClient` calls the Messages API (`claude-sonnet-5`) through a Salesforce Named Credential, with a JSON schema that requires one key per question.
4. **Check**: `AiGuard` drops unknown tokens, blocks contact details, requires sources and caps suggestions at three. An empty reply gets one retry without the schema.
5. **Confirm**: tokens are swapped back for names on screen; staff decide what to act on. The AI never contacts a customer.

Every call is logged to `AI_Call_Log__c` with tokens and cost, and capped at **200 calls a day** and **US$25 a month**. `LlmClient` is an interface, so tests run against `MockLlmClient` and no test ever calls the API.

## Guardrails

| Layer | What is enforced |
| --- | --- |
| Data in | Pseudonymous tokens; no children's data or allergy flags; contact details redacted |
| Prompt | Record text treated as data, never instructions; booking-stage glossary; versioned prompts |
| Output | JSON schema; unknown tokens dropped; sources required; max three tasks |
| Cost | Daily call cap, monthly budget, usage banner |
| People | Staff confirm every action; no customer messaging |
| Secrets | Anthropic key in an External Credential, granted by the `CommunityOS_AI_Access` permission set |

## Evaluation

Golden set: 8 real households × 6 desk questions, graded automatically against the masked record. Details in [`docs/eval-results.md`](docs/eval-results.md).

| Version | Correct (of 48) | Data leaks |
| --- | --- | --- |
| Rules only (no LLM) | 38 | 0 |
| Claude, prompt v6 | 44 | 0 |
| Claude, prompt v7 (booking-stage glossary) | 47 | 0 |

AI Insights: 28 of 28 rated useful after the empty-reply fix.

## Repo layout

| Path | Contents |
| --- | --- |
| `force-app/main/default` | Salesforce source: Apex classes and tests, `family360` LWC, objects, trigger, permission sets, layouts, profiles |
| `manifest/` | Production deploy manifests (`prod-visits`, `prod-family360`, `prod-households`, `prod-leadsearch`, `prod-ownerbrief`) |
| `n8n/` | Exported n8n workflow for the owner daily brief (no credentials inside) |
| `scripts/eval/` | Golden-set templates, run scripts and the Python grader |
| `scripts/apex/` | Anonymous Apex helpers used for loads and checks |
| `docs/` | Runbooks (production release, Square visit sync, enabling Claude, n8n setup), eval results, ERD, data map, decision records |
| `evals/` | Read-only access check for the planned MCP server |
| `mcp-server/`, `ingest/`, `ui/` | Empty placeholders reserved for the roadmap |

## Deploying

Requires the Salesforce CLI and an authorised org alias.

```
sf project deploy validate --manifest manifest/prod-family360.xml --target-org <alias> --test-level RunLocalTests
sf project deploy quick --job-id <validation job id> --target-org <alias>
```

Then follow [`docs/runbook-prod-release.md`](docs/runbook-prod-release.md) to create the Anthropic External Credential, assign permission sets and set `CommunityOS_Settings__c`. The Square sync and n8n setup have their own runbooks in `docs/`.

## Secrets and data

Nothing secret or personal is committed. Copy `.env.example` to `.env` locally. The Anthropic key lives in a Salesforce External Credential, the Square token in the org, and n8n keeps its own Salesforce (OAuth with PKCE) and Gmail credentials. Customer exports and eval outputs stay in `.local/`, which is git-ignored. Test data uses `555` phone numbers and `example.com` emails.

## Roadmap

The MVP is bare-minimum connectivity on purpose: one LLM path, minimal deterministic guardrails, one venue.

1. **Harden**: cheaper Ask, better identity matching, follow-up drafts that staff approve.
2. **Go headless**: expose Family 360 as MCP tools on [Salesforce Headless 360](https://www.salesforce.com/news/stories/salesforce-headless-360-announcement/), usable from Slack, n8n or any agent.
3. **Package**: a managed package or subscription for small businesses built around family wellness, starting with a second pilot venue.

## Author

Parminder Singh Bagga, Senior Salesforce Solution Architect, Spark Business Solutions, and owner of Fun Circle. [LinkedIn](https://www.linkedin.com/in/pbsalesforce)
