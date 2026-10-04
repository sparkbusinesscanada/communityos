/**
 * Last visit, visits this year, spend and visit mix for a family.
 * Reads Visit__c (Square orders copied nightly by SquareVisitSync). Counts one visit per day.
 * Falls back to Salesforce Orders when no Square visits are linked yet. Never calls Square.
 */
public with sharing class VisitSummaryService {
    public class Summary {
        @AuraEnabled public String source;
        @AuraEnabled public String lastVisit;
        @AuraEnabled public Integer visitsThisYear = 0;
        @AuraEnabled public Integer visitsLast90Days = 0;
        @AuraEnabled public Decimal spend12Months = 0;
        @AuraEnabled public String mix;
        @AuraEnabled public String note;
        public Date lastVisitDate;
    }

    public static Summary get(Id accountId) {
        Summary fromVisits = fromVisits(accountId);
        if (fromVisits != null) {
            return fromVisits;
        }
        Integer linked = [SELECT COUNT() FROM Contact WHERE AccountId = :accountId AND Square_Id__c != null WITH USER_MODE];
        return fromSalesforce(accountId, linked == 0
            ? 'No Square customer linked to this family.'
            : 'No Square visits synced for this family yet; showing Salesforce orders.');
    }

    private static Summary fromVisits(Id accountId) {
        List<Visit__c> visits = [
            SELECT Visited_At__c, Amount__c, Offering__c, Counts_As_Visit__c
            FROM Visit__c
            WHERE Household__c = :accountId AND Visited_At__c = LAST_N_DAYS:365
            WITH USER_MODE ORDER BY Visited_At__c DESC LIMIT 2000
        ];
        if (visits.isEmpty()) {
            return null;
        }
        Summary sm = new Summary();
        Integer year = Date.today().year();
        Date since90 = Date.today().addDays(-90);
        Set<Date> days = new Set<Date>();
        Set<Date> days90 = new Set<Date>();
        Map<String, Integer> mix = new Map<String, Integer>();
        for (Visit__c v : visits) {
            sm.spend12Months += v.Amount__c == null ? 0 : v.Amount__c;
            if (!v.Counts_As_Visit__c) {
                continue;
            }
            Date d = v.Visited_At__c.date();
            if (sm.lastVisitDate == null) {
                sm.lastVisitDate = d;
                sm.lastVisit = v.Visited_At__c.format('d MMM yyyy');
            }
            if (d.year() == year) { days.add(d); }
            if (d >= since90) { days90.add(d); }
            String k = v.Offering__c == null ? 'Other' : v.Offering__c;
            mix.put(k, (mix.containsKey(k) ? mix.get(k) : 0) + 1);
        }
        sm.visitsThisYear = days.size();
        sm.visitsLast90Days = days90.size();
        List<String> parts = new List<String>();
        for (String k : new List<String>{ 'Drop-in', 'Party', 'Laser tag', 'Camp', 'Café', 'Retail', 'Other' }) {
            if (mix.containsKey(k)) { parts.add(k + ' ' + mix.get(k)); }
        }
        sm.mix = String.join(parts, ' · ');
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
        sm.source = 'Square visits, synced nightly';
        if (s != null && s.Square_Last_Sync__c != null) {
            sm.source += ' (last sync ' + s.Square_Last_Sync__c.format('d MMM h:mm a') + ')';
        }
        return sm;
    }

    private static Summary fromSalesforce(Id accountId, String note) {
        Summary sm = new Summary();
        sm.source = 'Salesforce orders';
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
