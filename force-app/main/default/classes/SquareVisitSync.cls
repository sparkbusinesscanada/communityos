/**
 * Nightly copy of completed Square orders into Visit__c (read-only on the Square side).
 *
 * - Reads POST /v2/orders/search for the configured location, one page per Queueable run,
 *   and chains itself while Square returns a cursor.
 * - Keeps only orders that have a Square customer and real money (skips No-sale drawer opens).
 * - Upserts on Square_Order_Id__c, so re-running never creates duplicates.
 * - Matches the paying guardian by Contact.Square_Id__c; the household comes from the contact.
 * - Never copies card details, ticket names or anything about the children.
 * Runs without sharing on purpose: it is a system sync that must match every contact by Square id.
 */
public without sharing class SquareVisitSync implements Queueable, Database.AllowsCallouts {
    public static final String SQUARE_VERSION = '2025-01-23';
    @TestVisible static final Integer PAGE_SIZE = 500;
    @TestVisible static final Integer MAX_PAGES = 200;

    private final Integer days;
    private final String cursor;
    private final Integer page;
    private final Integer savedSoFar;

    public SquareVisitSync(Integer days) {
        this(days, null, 1, 0);
    }

    private SquareVisitSync(Integer days, String cursor, Integer page, Integer savedSoFar) {
        this.days = days == null || days < 1 ? 2 : days;
        this.cursor = cursor;
        this.page = page;
        this.savedSoFar = savedSoFar;
    }

    public void execute(QueueableContext ctx) {
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
        String location = s == null ? null : s.Square_Location_Id__c;
        if (String.isBlank(location)) {
            recordStatus('Skipped: no Square location set in CommunityOS Settings.');
            return;
        }
        Integer saved = savedSoFar;
        String next;
        try {
            HttpResponse res = new Http().send(buildRequest(location, days, cursor));
            if (res.getStatusCode() != 200) {
                recordStatus('Failed on page ' + page + ': Square returned ' + res.getStatusCode() + '. Nothing changed.');
                return;
            }
            Result r = ingest(res.getBody());
            saved += r.saved;
            next = r.cursor;
        } catch (Exception e) {
            recordStatus('Failed on page ' + page + ': ' + e.getMessage().left(200));
            return;
        }
        if (String.isNotBlank(next) && page < MAX_PAGES && !Test.isRunningTest()) {
            System.enqueueJob(new SquareVisitSync(days, next, page + 1, saved));
        } else {
            recordStatus('OK: ' + saved + ' visits saved from ' + page + ' page(s), last ' + days + ' day(s).');
        }
    }

    @TestVisible
    static HttpRequest buildRequest(String location, Integer days, String cursor) {
        Map<String, Object> body = new Map<String, Object>{
            'location_ids' => new List<String>{ location },
            'limit' => PAGE_SIZE,
            'query' => new Map<String, Object>{
                'filter' => new Map<String, Object>{
                    'state_filter' => new Map<String, Object>{ 'states' => new List<String>{ 'COMPLETED' } },
                    'date_time_filter' => new Map<String, Object>{
                        'closed_at' => new Map<String, Object>{
                            'start_at' => Datetime.now().addDays(-days).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                        }
                    }
                },
                'sort' => new Map<String, Object>{ 'sort_field' => 'CLOSED_AT', 'sort_order' => 'ASC' }
            }
        };
        if (String.isNotBlank(cursor)) {
            body.put('cursor', cursor);
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_Production/orders/search');
        req.setMethod('POST');
        req.setTimeout(60000);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Square-Version', SQUARE_VERSION);
        req.setBody(JSON.serialize(body));
        return req;
    }

    public class Result {
        public Integer received = 0;
        public Integer skipped = 0;
        public Integer saved = 0;
        public Integer matched = 0;
        public String cursor;
    }

    /** Parses one orders/search response and upserts the visits. Also used to load a sample file. */
    public static Result ingest(String responseBody) {
        Result r = new Result();
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        r.cursor = (String) body.get('cursor');
        List<Object> orders = body.get('orders') == null ? new List<Object>() : (List<Object>) body.get('orders');
        r.received = orders.size();

        List<Map<String, Object>> keep = new List<Map<String, Object>>();
        Set<String> customerIds = new Set<String>();
        for (Object o : orders) {
            Map<String, Object> om = (Map<String, Object>) o;
            String customerId = customerOf(om);
            if (customerId == null || cents(om.get('total_money')) == 0 || om.get('line_items') == null) {
                r.skipped++;
                continue;
            }
            customerIds.add(customerId);
            keep.add(om);
        }

        Map<String, Contact> byCustomer = new Map<String, Contact>();
        if (!customerIds.isEmpty()) {
            for (Contact c : [SELECT Id, AccountId, Square_Id__c FROM Contact WHERE Square_Id__c IN :customerIds]) {
                byCustomer.put(c.Square_Id__c, c);
            }
        }

        List<Visit__c> rows = new List<Visit__c>();
        Datetime now = Datetime.now();
        for (Map<String, Object> om : keep) {
            Visit__c v = toVisit(om, byCustomer);
            v.Last_Synced__c = now;
            if (v.Contact__c != null) {
                r.matched++;
            }
            rows.add(v);
        }
        if (!rows.isEmpty()) {
            for (Database.UpsertResult ur : Database.upsert(rows, Visit__c.Square_Order_Id__c, false)) {
                if (ur.isSuccess()) {
                    r.saved++;
                }
            }
        }
        return r;
    }

    @TestVisible
    static Visit__c toVisit(Map<String, Object> om, Map<String, Contact> byCustomer) {
        String customerId = customerOf(om);
        Contact c = byCustomer.get(customerId);
        Map<String, Object> source = (Map<String, Object>) om.get('source');
        List<Object> items = (List<Object>) om.get('line_items');

        Map<String, Decimal> byOffering = new Map<String, Decimal>();
        List<String> parts = new List<String>();
        Decimal qty = 0;
        Boolean cameIn = false;
        for (Object li : items) {
            Map<String, Object> lm = (Map<String, Object>) li;
            Decimal q = lm.get('quantity') == null ? 1 : Decimal.valueOf((String) lm.get('quantity'));
            qty += q;
            String name = itemLabel(lm);
            parts.add((q == q.round() ? String.valueOf(q.intValue()) : String.valueOf(q)) + 'x ' + name);
            String off = offeringFor((String) lm.get('name') + ' ' + (String) lm.get('variation_name'));
            Decimal amt = cents(lm.get('total_money'));
            if (!isPaymentOnly((String) lm.get('name'))) { cameIn = true; }
            byOffering.put(off, (byOffering.containsKey(off) ? byOffering.get(off) : 0) + amt);
        }

        String orderId = (String) om.get('id');
        return new Visit__c(
            Square_Order_Id__c = orderId,
            Square_Customer_Id__c = customerId,
            Contact__c = c == null ? null : c.Id,
            Household__c = c == null ? null : c.AccountId,
            Visited_At__c = parseTime((String) om.get('closed_at')),
            Amount__c = cents(om.get('total_money')) / 100,
            Tax__c = cents(om.get('total_tax_money')) / 100,
            Tip__c = cents(om.get('total_tip_money')) / 100,
            Discount__c = cents(om.get('total_discount_money')) / 100,
            Item_Count__c = qty,
            Counts_As_Visit__c = cameIn,
            Item_Summary__c = String.join(parts, ', ').abbreviate(255),
            Offering__c = topOffering(byOffering),
            Location_Id__c = (String) om.get('location_id'),
            Channel__c = source == null ? null : (String) source.get('name'),
            Source_System__c = 'Square',
            Source_URL__c = 'https://connect.squareup.com/v2/orders/' + orderId
        );
    }

    /** Keyword rules from Fun Circle's Square catalog. First match wins, so order matters. */
    @TestVisible
    static String offeringFor(String text) {
        String t = text == null ? '' : text.toLowerCase();
        if (t.contains('cash back') || t.contains('gift card')) { return 'Other'; }
        if (t.contains('laser')) { return 'Laser tag'; }
        if (t.contains('party') || t.contains('birthday') || t.contains('face paint') || t.contains('balloon') || t.contains('deposit') || t.contains('event')) { return 'Party'; }
        if (t.contains('camp') || t.contains('class') || t.contains('program')) { return 'Camp'; }
        if (t.contains('sock')) { return 'Retail'; }
        for (String food : new List<String>{ 'pizza', 'coffee', 'latte', 'juice', 'water', 'gatorade', 'soda',
                'snack', 'chip', 'fries', 'nugget', 'popcorn', 'slush', 'cookie', 'muffin', 'ice cream', 'drink',
                'candy', 'chocolate', 'pringles', 'doritos', 'food', 'sandwich', 'hot dog', 'milk' }) {
            if (t.contains(food)) { return 'Café'; }
        }
        if (t.contains('admission') || t.contains('drop') || t.contains('play') || t.contains('entry')
            || t.contains('pass') || t.contains('toddler') || t.contains('sibling') || t.contains('member')
            || t.contains('punch') || t.contains('kid') || t.contains('child') || t.contains('adult')) { return 'Drop-in'; }
        return 'Other';
    }

    /** Lines that are money movement only: nobody came in for these. */
    @TestVisible
    static Boolean isPaymentOnly(String name) {
        String t = name == null ? '' : name.toLowerCase();
        return t.contains('deposit') || t.contains('cash back') || t.contains('gift card');
    }

    private static String topOffering(Map<String, Decimal> byOffering) {
        String best = 'Other';
        Decimal bestAmt = -1;
        for (String k : new List<String>{ 'Party', 'Laser tag', 'Camp', 'Drop-in', 'Café', 'Retail', 'Other' }) {
            if (byOffering.containsKey(k) && byOffering.get(k) > bestAmt) {
                best = k;
                bestAmt = byOffering.get(k);
            }
        }
        return best;
    }

    private static String itemLabel(Map<String, Object> lm) {
        String name = (String) lm.get('name');
        String variation = (String) lm.get('variation_name');
        if (String.isBlank(name)) { return 'Custom amount'; }
        return String.isBlank(variation) || variation == 'Regular' ? name : name + ' (' + variation + ')';
    }

    private static String customerOf(Map<String, Object> om) {
        String id = (String) om.get('customer_id');
        if (String.isNotBlank(id)) { return id; }
        List<Object> tenders = (List<Object>) om.get('tenders');
        if (tenders != null) {
            for (Object t : tenders) {
                String tid = (String) ((Map<String, Object>) t).get('customer_id');
                if (String.isNotBlank(tid)) { return tid; }
            }
        }
        return null;
    }

    private static Decimal cents(Object money) {
        if (money == null) { return 0; }
        Object amount = ((Map<String, Object>) money).get('amount');
        return amount == null ? 0 : Decimal.valueOf(String.valueOf(amount));
    }

    private static Datetime parseTime(String iso) {
        return iso == null ? null : (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
    }

    @TestVisible
    static void recordStatus(String status) {
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
        if (s == null || s.Id == null) {
            s = new CommunityOS_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        s.Square_Last_Sync__c = Datetime.now();
        s.Square_Sync_Status__c = status.abbreviate(255);
        upsert s;
    }
}
