# 001 — Salesforce replaces Supabase as the Family Graph

- Status: Accepted
- Date: 2026-09-22 (D01)
- Decider: Parminder Singh Bagga

## Context
The original plan put the Family Graph in Supabase Postgres, with RLS for tenant isolation and n8n copying Square, Salesforce and waiver data into it. Tenant #1 (Fun Circle) already runs on Salesforce Enterprise Edition (instance CAN36). Its org holds 18,880 guardian Contacts synced both ways with Square, 5,228 Accounts, 151 children in Minor__c, 2,074 party bookings (Opportunity), 243 camp registrations (Participant__c) and 98 waiver Contracts. It also has working Apex for deposits, camp PDFs and the Square sync.

## Decision
Salesforce is the system of record and the Family Graph. There is no Supabase.
- Graph = Account (Household RT) → Contact (guardians) + Minor__c (children) → Opportunity, Participant__c, Check_In__c, and the new Visit__c, Enquiry__c, Waiver__c. Plus Desk_Question__c, Merge_Candidate__c and Agent_Event__c.
- "SQL" in the plan and gates now means SOQL.
- Isolation = one org per operator. CommunityOS metadata ships as an unlocked package; tenant #2 is a scratch org with the package and synthetic data.
- Agents read through a TypeScript MCP server (jsforce) authenticated by JWT as a Salesforce Integration user with CommunityOS_Graph_Read (no create, edit or delete). The agent runtime logs to Agent_Event__c through a separate insert-only permission set.
- Deterministic work stays in Flows, Apex, SOQL and roll-ups. n8n does ingestion and the 7:30 am schedule.

## Why
1. **The data is already there.** Copying 18.9k contacts and every booking into Postgres adds a sync that can drift, and loading Fun Circle's full history (a W1 gate item) becomes a two-way reconciliation problem.
2. **Isolation gets stronger and simpler.** A separate org per operator is physical isolation. RLS policies were the riskiest part of the Supabase design and are gone. The rule "isolation below the agent, never in the prompt" still holds, now enforced by org boundary plus the permission set.
3. **Least privilege is declarative and testable.** Object and field-level security gives a read-only agent user in metadata. evals/us006-readonly.ts proves it on every change.
4. **Data residency.** The org is on a Canadian instance, so the Canadian-residency question an outside operator may raise in an LOI is already answered.
5. **Skills and time.** This is the owner's core platform. It removes a new stack (Supabase, RLS, migrations) from a 16-day build.
6. **Cost.** Supabase Pro is dropped. Salesforce Integration user licences are included (5 available, 0 used).

## Consequences
- Children stay in Minor__c. Contact child fields are unused and are not part of the graph.
- Existing objects are extended only minimally (3 Contact fields, 1 Minor__c formula, 1 Account record type) so the live Square sync and booking Apex are untouched.
- An outside operator must be on Salesforce, or be provisioned an org. That narrows the ICP for the W4 LOI, and discovery interviews should note each venue's current system.
- API limits (Enterprise: 100k+ calls/24h) and Data Storage (Visit__c at one row per Square order) need watching. Revisit at 50k Visits.
- Unlocked-package constraints apply: no hard dependency on Fun Circle–only objects in the core package. Minor__c, Participant__c, Camp__c and Check_In__c references need an extension package or an adapter before tenant #2. **Open item for D03+.**
- Staff tally entry uses the licensed desk user info@funcircle.ca via the "Log desk question" global action.

## Rejected alternatives
- **Supabase + RLS (original).** Duplicate store, sync drift, RLS risk, new stack.
- **Salesforce as source with a Postgres read replica for agents.** Two stores for no MVP benefit.
