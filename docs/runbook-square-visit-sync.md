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

## Go-live in production
1. Deploy `Visit__c`, the `CommunityOS_Offering` and `CommunityOS_Source_System` value sets, the settings fields, the classes and the permission set.
2. Backfill 12 months once:
   ```
   sf apex run -o prod
   ```
   then paste `System.enqueueJob(new SquareVisitSync(365));`
3. Schedule nightly: run `scripts/apex/schedule-square-visit-sync.apex`.
4. Check `Square_Sync_Status__c` the next morning.

## COS sandbox
COS has no Square token on purpose, so the scheduled run records "Square returned 401" and writes nothing. Demo visits were loaded once from a read-only Square export through `SquareVisitSync.ingest` (`.local/`, not committed).

## Known gap
Most walk-in orders have no customer attached at the till, so they cannot be linked to a family. Attaching the customer in Square at checkout is what makes visit history complete.
