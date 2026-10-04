# Square visit sync (US-017)

## What it does
- Every night at 2:30 am, `SquareVisitSyncJob` reads completed Square orders from the last 2 days (`POST /v2/orders/search`, read-only) and upserts them into `Visit__c` on `Square_Order_Id__c`.
- Keeps only orders with a Square customer and a non-zero total. No-sale drawer opens and anonymous walk-ins are skipped.
- Matches the paying guardian by `Contact.Square_Id__c`; the household comes from that contact.
- Copies totals, tax, tip, discount, item names and quantities, offering and channel. Never copies card details, ticket names or anything about the children.
- `Counts_As_Visit__c` is false for deposit, gift card or cash-back only orders: they count as spend but not as visit days.
- Result of each run: `CommunityOS_Settings__c.Square_Sync_Status__c` and `Square_Last_Sync__c`.

## Where it shows up
- Family 360 stats: last visit, visit days this year, spend over the last 12 months, visit mix.
- Segments: "Regular visitor" when there are 3 or more visit days in the last 90 days; "Lapsed" uses the latest visit.
- AI context: `squareVisits` aggregate only (visit days, spend, mix). No order ids or item lines.

## Settings (CommunityOS Settings, org default)
| Field | Value |
|---|---|
| Square_Location_Id__c | L7A9E1RN6DM8D |
| Square_Sync_Days__c | 2 (blank means 2) |

## Authentication
The named credential `Square_Production` only supplies the base URL. The access token comes from `Square_Config__mdt.Production.Access_Token__c` through `SquareIntegrationConstants.getAccessToken()`, the same source the existing Square integration uses. Nothing new is stored.

## Production (live since 4 Oct 2026)
- Deployed with `manifest/prod-visits.xml` (validate, then quick deploy; `SquareVisitSyncTest` 5/5, coverage 95% / 100%).
- Settings org default: location L7A9E1RN6DM8D, 2 sync days.
- Nightly job "CommunityOS Square visit sync" at 2:30 am Pacific.
- 12-month backfill run on 4 Oct 2026.
- Permission set `CommunityOS_Visits_Read` gives staff read-only access.

## Go-live steps (for reference)
1. Deploy `Visit__c`, the `CommunityOS_Offering` and `CommunityOS_Source_System` value sets, the settings fields, the classes and the permission set.
2. Backfill 12 months once:
   ```
   sf apex run -o prod
   ```
   then paste `System.enqueueJob(new SquareVisitSync(365));`
3. Schedule nightly: run `scripts/apex/schedule-square-visit-sync.apex`.
4. Check `Square_Sync_Status__c` the next morning.

## COS sandbox
Custom metadata is copied on sandbox refresh, so COS holds the production Square token in `Square_Config__mdt`. The COS copy of `SquareVisitSync` predates the token header and records "Square returned 401". Demo visits were loaded once from a read-only Square export through `SquareVisitSync.ingest` (`.local/`, not committed).

## Known gap
Most walk-in orders have no customer attached at the till, so they cannot be linked to a family. Attaching the customer in Square at checkout is what makes visit history complete.
