# CommunityOS

CommunityOS is the operations layer for family-activity venues — one Family Graph, narrow AI agents, humans approve.

## Layout
- db/migrations — Supabase Postgres schema and RLS policies
- ingest — n8n workflow exports (Square, Salesforce, waiver index)
- mcp-server — read-only MCP server over the Family Graph
- agents — Desk and Ops Brief agents
- evals — golden questions and scoring
- ui — staff-facing surfaces
- docs — decisions, runbooks, discovery notes

## Secrets
Never committed. Copy .env.example to .env locally. Master copies live in the password manager; runtime copies live in n8n credentials.
