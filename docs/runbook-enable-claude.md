# Runbook — switch CommunityOS from mock to Claude

Everything is deployed. Only two manual steps remain, both done by Parminder (the API key is never shared with Claude or committed).

## 1. Store the API key in Salesforce (2 min)

1. Setup → Named Credentials → **External Credentials** tab → **Anthropic**.
2. Principals → **ApiKey** → Edit (create it if the list is empty: Parameter Name `ApiKey`, Sequence 1).
3. Authentication Parameters → **Add** → Name `ApiKey`, Value = your Anthropic API key → Save.

The `CommunityOS_Family360` permission set already grants access to this principal.

## 2. Turn Claude on (1 min)

Setup → Custom Settings → **CommunityOS Settings** → Manage → New (org default):

| Field | Value |
|---|---|
| LLM Provider | `claude` |
| LLM Model | `claude-sonnet-5` |
| Max Output Tokens | `4096` |

To switch back to the free mock, clear LLM Provider.

## 3. Verify

- Family 360 → open a household → **Get insights**. The footer should show the Claude model name.
- AI Call Logs tab → newest row: Status `Success`, Context Sent shows tokens (Person A, Booking 1), no names.
- Rerun the eval (docs/eval-results.md) and fill in the Claude column.
