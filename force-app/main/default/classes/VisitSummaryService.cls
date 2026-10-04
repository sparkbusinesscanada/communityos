/**
 * Last visit, visits this year and spend for a family. Reads Square live (read-only, orders/search)
 * through the Square_Production named credential when it answers; otherwise falls back to the
 * Square orders already synced into Salesforce. Never writes to Square.
 */
public with sharing class VisitSummaryService {
    public class Summary {
        @AuraEnabled public String source;
        @AuraEnabled public String lastVisit;
        @AuraEnabled public Integer visitsThisYear = 0;
        @AuraEnabled public Decimal spend12Months = 0;
        @AuraEnabled public String note;
    }

    public static Summary get(Id accountId) {
        Set<String> squareIds = new Set<String>();
        for (Contact c : [SELECT Square_Id__c FROM Contact WHERE AccountId = :accountId AND Square_Id__c != null WITH USER_MODE LIMIT 10]) {
            squareIds.add(c.Square_Id__c);
        }
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getInstance();
        String location = s == null ? null : s.Square_Location_Id__c;
        if (!squareIds.isEmpty() && String.isNotBlank(location)) {
            try {
                Summary live = fromSquare(new List<String>(squareIds), location);
                if (live != null) { return live; }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Square read failed: ' + e.getMessage());
            }
        }
        return fromSalesforce(accountId, squareIds.isEmpty() ? 'No Square customer linked to this family.' :
            'Live Square is not reachable here; showing Square orders synced to Salesforce.');
    }

    @TestVisible
    private static Summary fromSquare(List<String> customerIds, String locationId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_Production/orders/search');
        req.setMethod('POST');
        req.setTimeout(10000);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Square-Version', '2025-01-23');
        req.setBody(JSON.serialize(new Map<String, Object>{
            'location_ids' => new List<String>{ locationId },
            'limit' => 100,
            'query' => new Map<String, Object>{
                'filter' => new Map<String, Object>{
                    'customer_filter' => new Map<String, Object>{ 'customer_ids' => customerIds },
                    'state_filter' => new Map<String, Object>{ 'states' => new List<String>{ 'COMPLETED' } },
                    'date_time_filter' => new Map<String, Object>{
                        'closed_at' => new Map<String, Object>{ 'start_at' => Datetime.now().addDays(-365).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') }
                    }
                },
                'sort' => new Map<String, Object>{ 'sort_field' => 'CLOSED_AT', 'sort_order' => 'DESC' }
            }
        }));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            return null;
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Summary sm = new Summary();
        sm.source = 'Square (live)';
        Integer year = Date.today().year();
        List<Object> orders = body.get('orders') == null ? new List<Object>() : (List<Object>) body.get('orders');
        for (Object o : orders) {
            Map<String, Object> om = (Map<String, Object>) o;
            String closed = (String) om.get('closed_at');
            Datetime dt = closed == null ? null : (Datetime) JSON.deserialize('"' + closed + '"', Datetime.class);
            if (dt != null && sm.lastVisit == null) { sm.lastVisit = dt.format('d MMM yyyy'); }
            if (dt != null && dt.year() == year) { sm.visitsThisYear++; }
            Map<String, Object> money = (Map<String, Object>) om.get('total_money');
            if (money != null && money.get('amount') != null) {
                sm.spend12Months += Decimal.valueOf(String.valueOf(money.get('amount'))) / 100;
            }
        }
        if (orders.isEmpty()) { sm.note = 'No completed Square orders in the last 12 months.'; }
        return sm;
    }

    private static Summary fromSalesforce(Id accountId, String note) {
        Summary sm = new Summary();
        sm.source = 'Salesforce (synced Square orders)';
        sm.note = note;
        Integer year = Date.today().year();
        Date since = Date.today().addDays(-365);
        for (Order o : [
            SELECT EffectiveDate, Total_Amount_with_Taxes__c, Invoice_Status__c
            FROM Order WHERE AccountId = :accountId AND EffectiveDate <= TODAY WITH USER_MODE
            ORDER BY EffectiveDate DESC LIMIT 200
        ]) {
            if (sm.lastVisit == null && o.EffectiveDate != null) {
                sm.lastVisit = Datetime.newInstance(o.EffectiveDate, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy');
            }
            if (o.EffectiveDate != null && o.EffectiveDate.year() == year) { sm.visitsThisYear++; }
            if (o.Invoice_Status__c == 'PAID' && o.EffectiveDate >= since && o.Total_Amount_with_Taxes__c != null) {
                sm.spend12Months += o.Total_Amount_with_Taxes__c;
            }
        }
        return sm;
    }
}
