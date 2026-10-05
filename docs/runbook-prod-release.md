# Production release: Family 360 + AI (US-016 to US-018)

Target org: `funcircle` (production). Package: `manifest/prod-family360.xml`.
Already live in production: Square visit sync (US-017).

## What ships
- **Screen and app:** Family 360 tab and screen; AI Call Log tab. Both tabs are visible to Fun Circle Sales and System Administrator. The CommunityOS app is **not** deployed.
- **Objects:** AI_Call_Log__c, Desk_Question__c, Family_Enquiry__c, Desk_Question_Template__mdt (10 questions), and new fields on Account, Activity and CommunityOS Settings.
- **Apex:** 29 classes (services, guardrails, Claude client, rules client, nightly rebooking job, tests).
- **Anthropic credential:** the `Anthropic_API` named credential and the `Anthropic` external credential. The API key is **not** in metadata.
- **Access:**
  - Profiles: Fun Circle Sales and System Administrator get object, field, Apex class and tab access.
  - Permission set `CommunityOS_AI_Access` grants use of the Anthropic key (profiles cannot hold this).
  - Permission set `CommunityOS_Family360` stays as a fallback for other users.

## Steps
| # | Step | Who | Reversible |
|---|---|---|---|
| 1 | Dry-run validate with all 11 test classes | Claude | Nothing changes |
| 2 | Quick deploy the validated package | Claude, after your OK | Yes (remove tab access / delete metadata) |
| 3 | Assign `CommunityOS_AI_Access` to active users on both profiles (`scripts/apex/assign-ai-access.apex`) | Claude | Yes |
| 4 | Paste the Anthropic API key: Setup > Named Credentials > External Credentials > Anthropic > Principals > ApiKey > Edit | **You** | Yes |
| 5 | CommunityOS Settings: provider `claude`, model `claude-sonnet-5`, max tokens 4096, cost $2 / $10 per MTok, daily cap 200, monthly budget (your number), live writes **off** | Claude | Yes |
| 6 | Schedule the nightly rebooking reminders (`scripts/apex/schedule-rebooking-job.apex`) | Claude | Yes |
| 7 | Smoke test on one family: insight, one desk question, the usage banner, the call log | You + Claude | — |

## Behaviour in production with live writes off
- **Allowed:** staff notes, follow-up tasks and enquiry records are saved.
- **Leads:** "New party" drafts are **held**, because production sends emails on new Leads.
- **Bookings:** "Change booking" drafts are **held**, because a booking change can sync to live Square.
- **Orders:** never written from Family 360.
- **AI:** suggests and answers only. Every task needs a staff click, and nothing is ever sent to a customer.

## Kill switches
- **AI off immediately:** CommunityOS Settings > LLM Provider = `mock` (rules mode, no API calls).
- **Spending:** the daily cap and monthly budget pause the AI automatically with a plain message.
- **Screen off:** remove the Family 360 tab from the two profiles.

## Known risk
Production tests run as the deploying admin. The profile changes in the same package should give the admin access to the new fields. If validation still fails on field access, deploy in two steps (objects, fields, profiles and permission sets first, then Apex and the screen).
