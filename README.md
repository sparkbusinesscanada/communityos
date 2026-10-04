# CommunityOS

CommunityOS is the operations layer for family-activity venues — one Family Graph, narrow AI agents, humans approve.

## Architecture
- Salesforce is the system of record and the Family Graph (one org per operator). See docs/decisions/001-salesforce-as-graph.md and docs/erd.md.
- n8n ingests Gmail enquiries, Square orders and the waiver index, and runs the 7:30 am schedule.
- Flows, Apex, SOQL and roll-ups do everything that must be exactly right (money, rosters, matching).
- A read-only TypeScript MCP server (jsforce, integration user) exposes the graph to the Desk Agent and Ops Brief.

## Layout
- force-app — SFDX source (objects, fields, permission sets, actions, reports)
- scripts — sf CLI helpers (deploy, integration user setup)
- ingest — n8n workflow exports
- mcp-server — read-only MCP server over the Family Graph
- agents — Desk Agent and Ops Brief
- evals — golden questions, scoring, security evals
- docs — ERD, decision records, runbooks

## Secrets
Never committed. Copy .env.example to .env locally. Master copies live in the password manager; n8n keeps its own credentials (Gmail, Square, Salesforce). The JWT private key lives outside the repo.
