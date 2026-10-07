/**
 * Read-only weekly business review data, called every Monday by the n8n "Weekly business review" workflow.
 * GET /services/apexrest/communityos/weekly
 *
 * Deterministic: counts only, computed from Leads, party Opportunities and Opportunity field history.
 * No names, phone numbers, emails or children's data leave Salesforce. n8n applies fixed rules
 * to these numbers and only then asks Claude to interpret them.
 */
@RestResource(urlMapping='/communityos/weekly')
global with sharing class OwnerWeeklyApi {
    public static final Integer MATCH_WINDOW_DAYS = 60;

    global class Period {
        public String label;
        public String fromDate;
        public String toDate;
        public Integer leads = 0;
        public Integer partyEnquiries = 0;
        public Integer partyEnquiriesConfirmed = 0;
        public Integer cancellations = 0;
    }

    global class Month {
        public String month;
        public Integer leads = 0;
        public Integer partiesHeld = 0;
        public Integer kids = 0;
        public Integer avgDaysBookedAhead;
    }

    global class Cohort {
        public String label;
        public Integer leads = 0;
        public Integer leadsThatBooked = 0;
        public Decimal conversionPct;
    }

    global class Count {
        public String name;
        public Integer count;
        public Count(String name, Integer count) {
            this.name = name;
            this.count = count;
        }
    }

    global class Weekly {
        public String weekEnding;
        public List<Period> periods = new List<Period>();
        public List<Cohort> cohorts = new List<Cohort>();
        public List<Count> leadSourcesLast28Days = new List<Count>();
        public Integer partiesOnBooksNext28Days = 0;
        public Integer partiesOnBooksSamePointLastYear = 0;
        public List<Month> months = new List<Month>();
        public List<Count> bookingChangesLast90Days = new List<Count>();
        public List<Count> dateChangeReasonsLast90Days = new List<Count>();
        public List<Count> cancellationReasonsLast90Days = new List<Count>();
        public Integer openPartyEnquiries = 0;
        public Integer oldestOpenEnquiryDays;
        public Integer rebookingCandidatesNext30Days = 0;
        public Integer unpaidOver30Days = 0;
        public Decimal unpaidOver30DaysTotal = 0;
        public Integer dropInsLast7Days = 0;
        public Integer dropInsPrior7Days = 0;
        public Decimal aiCostThisMonth = 0;
        public Decimal aiMonthlyBudget;
    }

    @HttpGet
    global static Weekly get() {
        return build(Date.today());
    }

    public static Weekly build(Date today) {
        Weekly w = new Weekly();
        w.weekEnding = String.valueOf(today.addDays(-1));
        w.periods.add(period('Last 7 days', today.addDays(-7), today));
        w.periods.add(period('Previous 7 days', today.addDays(-14), today.addDays(-7)));
        w.periods.add(period('Last 28 days', today.addDays(-28), today));
        w.periods.add(period('Same 28 days last year', today.addDays(-28 - 364), today.addDays(-364)));
        w.cohorts.add(cohort('Leads from 30 to 90 days ago', today.addDays(-90), today.addDays(-30)));
        w.cohorts.add(cohort('Leads from 90 to 150 days ago', today.addDays(-150), today.addDays(-90)));
        addLeadSources(w, today);
        addPace(w, today);
        addMonths(w, today);
        addChanges(w, today);

        OwnerBriefApi.Brief b = OwnerBriefApi.build(today);
        w.openPartyEnquiries = b.openPartyEnquiries;
        w.oldestOpenEnquiryDays = b.oldestOpenEnquiryDays;
        w.rebookingCandidatesNext30Days = b.rebookingCandidatesNext30Days;
        w.unpaidOver30Days = b.unpaidOver30Days;
        w.unpaidOver30DaysTotal = b.unpaidOver30DaysTotal;
        w.dropInsLast7Days = b.dropInsLast7Days;
        w.dropInsPrior7Days = b.dropInsPrior7Days;
        w.aiCostThisMonth = b.aiCostThisMonth;
        w.aiMonthlyBudget = b.aiMonthlyBudget;
        return w;
    }

    private static Datetime startOf(Date d) {
        return Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
    }

    private static Boolean isConfirmed(Opportunity o) {
        return o.IsWon || OwnerBriefApi.CONFIRMED_STAGES.contains(o.StageName);
    }

    /** Leads, party enquiries (opportunities created), how many of those are now confirmed, and cancellations. */
    @TestVisible
    private static Period period(String label, Date fromDate, Date toDate) {
        Period p = new Period();
        p.label = label;
        p.fromDate = String.valueOf(fromDate);
        p.toDate = String.valueOf(toDate.addDays(-1));
        Datetime f = startOf(fromDate);
        Datetime t = startOf(toDate);
        p.leads = [SELECT COUNT() FROM Lead WHERE CreatedDate >= :f AND CreatedDate < :t WITH USER_MODE];
        for (Opportunity o : [
            SELECT StageName, IsWon FROM Opportunity
            WHERE Booking_Type__c = 'Party' AND CreatedDate >= :f AND CreatedDate < :t
            WITH USER_MODE LIMIT 5000
        ]) {
            p.partyEnquiries++;
            if (isConfirmed(o)) { p.partyEnquiriesConfirmed++; }
        }
        for (OpportunityFieldHistory h : [
            SELECT NewValue FROM OpportunityFieldHistory
            WHERE Field = 'StageName' AND Opportunity.Booking_Type__c = 'Party' AND CreatedDate >= :f AND CreatedDate < :t
            WITH USER_MODE LIMIT 5000
        ]) {
            if (String.valueOf(h.NewValue) == 'Closed Lost') { p.cancellations++; }
        }
        return p;
    }

    /**
     * Share of leads that became a party booking within 60 days. Leads are rarely converted in
     * Salesforce, so a lead counts as booked when a household with the same phone (households are
     * named by phone) or a contact with the same email has a party opportunity created from the
     * lead date up to 60 days later. Only counts leave this method.
     */
    @TestVisible
    private static Cohort cohort(String label, Date fromDate, Date toDate) {
        Cohort c = new Cohort();
        c.label = label;
        Datetime f = startOf(fromDate);
        Datetime t = startOf(toDate);
        List<Lead> leads = [SELECT CreatedDate, Phone, Email FROM Lead WHERE CreatedDate >= :f AND CreatedDate < :t WITH USER_MODE LIMIT 5000];
        c.leads = leads.size();
        if (leads.isEmpty()) { return c; }
        Set<String> phones = new Set<String>();
        Set<String> emails = new Set<String>();
        for (Lead l : leads) {
            String p = digits(l.Phone);
            if (p != null) { phones.add(p); }
            if (String.isNotBlank(l.Email)) { emails.add(l.Email.toLowerCase()); }
        }
        Map<String, Set<Id>> householdsByKey = new Map<String, Set<Id>>();
        for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :phones WITH USER_MODE LIMIT 5000]) {
            key(householdsByKey, 'p:' + a.Name, a.Id);
        }
        for (Contact ct : [SELECT AccountId, Email FROM Contact WHERE Email IN :emails AND AccountId != null WITH USER_MODE LIMIT 5000]) {
            key(householdsByKey, 'e:' + ct.Email.toLowerCase(), ct.AccountId);
        }
        Set<Id> households = new Set<Id>();
        for (Set<Id> ids : householdsByKey.values()) { households.addAll(ids); }
        Map<Id, List<Datetime>> bookingsByHousehold = new Map<Id, List<Datetime>>();
        Datetime until = t.addDays(MATCH_WINDOW_DAYS);
        for (Opportunity o : [
            SELECT AccountId, CreatedDate FROM Opportunity
            WHERE Booking_Type__c = 'Party' AND AccountId IN :households AND CreatedDate >= :f.addDays(-1) AND CreatedDate < :until
            WITH USER_MODE LIMIT 5000
        ]) {
            if (!bookingsByHousehold.containsKey(o.AccountId)) { bookingsByHousehold.put(o.AccountId, new List<Datetime>()); }
            bookingsByHousehold.get(o.AccountId).add(o.CreatedDate);
        }
        for (Lead l : leads) {
            Set<Id> candidates = new Set<Id>();
            String p = digits(l.Phone);
            if (p != null && householdsByKey.containsKey('p:' + p)) { candidates.addAll(householdsByKey.get('p:' + p)); }
            if (String.isNotBlank(l.Email) && householdsByKey.containsKey('e:' + l.Email.toLowerCase())) {
                candidates.addAll(householdsByKey.get('e:' + l.Email.toLowerCase()));
            }
            if (bookedAfter(candidates, bookingsByHousehold, l.CreatedDate)) { c.leadsThatBooked++; }
        }
        c.conversionPct = (Decimal.valueOf(c.leadsThatBooked) * 100 / c.leads).setScale(1);
        return c;
    }

    private static Boolean bookedAfter(Set<Id> households, Map<Id, List<Datetime>> bookings, Datetime leadCreated) {
        for (Id h : households) {
            if (!bookings.containsKey(h)) { continue; }
            for (Datetime created : bookings.get(h)) {
                if (created >= leadCreated.addDays(-1) && created < leadCreated.addDays(MATCH_WINDOW_DAYS)) { return true; }
            }
        }
        return false;
    }

    private static void key(Map<String, Set<Id>> m, String k, Id v) {
        if (!m.containsKey(k)) { m.put(k, new Set<Id>()); }
        m.get(k).add(v);
    }

    @TestVisible
    private static String digits(String phone) {
        if (String.isBlank(phone)) { return null; }
        String d = phone.replaceAll('[^0-9]', '');
        if (d.length() == 11 && d.startsWith('1')) { d = d.substring(1); }
        return d.length() == 10 ? d : null;
    }

    private static void addLeadSources(Weekly w, Date today) {
        Datetime f = startOf(today.addDays(-28));
        for (AggregateResult ar : [
            SELECT LeadSource s, COUNT(Id) n FROM Lead WHERE CreatedDate >= :f
            WITH USER_MODE GROUP BY LeadSource ORDER BY COUNT(Id) DESC LIMIT 10
        ]) {
            w.leadSourcesLast28Days.add(new Count(ar.get('s') == null ? 'Not recorded' : String.valueOf(ar.get('s')), (Integer) ar.get('n')));
        }
    }

    /** Parties on the books for the next 28 days, compared with what was on the books at this point last year. */
    private static void addPace(Weekly w, Date today) {
        Datetime nowStart = startOf(today);
        Datetime in28 = startOf(today.addDays(28));
        w.partiesOnBooksNext28Days = [
            SELECT COUNT() FROM Opportunity WHERE Booking_Type__c = 'Party' AND StageName != 'Closed Lost'
              AND Event_Date_and_Start_Time__c >= :nowStart AND Event_Date_and_Start_Time__c < :in28 WITH USER_MODE
        ];
        Datetime lyStart = startOf(today.addDays(-364));
        Datetime ly28 = startOf(today.addDays(-364 + 28));
        // Created by this point last year; cancellations after that point still count, as they were on the books then
        w.partiesOnBooksSamePointLastYear = [
            SELECT COUNT() FROM Opportunity WHERE Booking_Type__c = 'Party' AND CreatedDate < :lyStart
              AND Event_Date_and_Start_Time__c >= :lyStart AND Event_Date_and_Start_Time__c < :ly28 WITH USER_MODE
        ];
    }

    /** Last 24 full months: leads, parties held, kids, and how far ahead parties were booked. */
    @TestVisible
    private static void addMonths(Weekly w, Date today) {
        Date firstOfThisMonth = today.toStartOfMonth();
        Date fromMonth = firstOfThisMonth.addMonths(-24);
        Map<String, Month> byKey = new Map<String, Month>();
        for (Integer i = 0; i < 24; i++) {
            Date d = fromMonth.addMonths(i);
            Month m = new Month();
            m.month = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('yyyy-MM');
            byKey.put(m.month, m);
            w.months.add(m);
        }
        Datetime f = startOf(fromMonth);
        Datetime t = startOf(firstOfThisMonth);
        for (AggregateResult ar : [
            SELECT CALENDAR_YEAR(CreatedDate) y, CALENDAR_MONTH(CreatedDate) mo, COUNT(Id) n FROM Lead
            WHERE CreatedDate >= :f AND CreatedDate < :t
            WITH USER_MODE GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)
        ]) {
            Month m = byKey.get(monthKey((Integer) ar.get('y'), (Integer) ar.get('mo')));
            if (m != null) { m.leads = (Integer) ar.get('n'); }
        }
        Map<String, Long> aheadTotal = new Map<String, Long>();
        for (Opportunity o : [
            SELECT StageName, IsWon, Estimated_Children__c, CreatedDate, Event_Date_and_Start_Time__c FROM Opportunity
            WHERE Booking_Type__c = 'Party' AND StageName != 'Closed Lost'
              AND Event_Date_and_Start_Time__c >= :f AND Event_Date_and_Start_Time__c < :t
            WITH USER_MODE LIMIT 10000
        ]) {
            if (!isConfirmed(o)) { continue; }
            Month m = byKey.get(o.Event_Date_and_Start_Time__c.format('yyyy-MM'));
            if (m == null) { continue; }
            m.partiesHeld++;
            m.kids += o.Estimated_Children__c == null ? 0 : o.Estimated_Children__c.intValue();
            Integer ahead = Math.max(0, o.CreatedDate.date().daysBetween(o.Event_Date_and_Start_Time__c.date()));
            aheadTotal.put(m.month, (aheadTotal.containsKey(m.month) ? aheadTotal.get(m.month) : 0) + ahead);
        }
        for (Month m : w.months) {
            if (m.partiesHeld > 0) { m.avgDaysBookedAhead = (Integer) (aheadTotal.get(m.month) / m.partiesHeld); }
        }
    }

    private static String monthKey(Integer y, Integer mo) {
        return String.valueOf(y) + '-' + (mo < 10 ? '0' : '') + String.valueOf(mo);
    }

    /** What changes on party bookings after they are made (a field going from one value to another). */
    @TestVisible
    private static void addChanges(Weekly w, Date today) {
        Map<String, String> labels = new Map<String, String>{
            'Activity_Room__c' => 'Room changed',
            'Estimated_Adults__c' => 'Adult count changed',
            'Estimated_Children__c' => 'Kid count changed',
            'Party_Package__c' => 'Package changed',
            'Requested_Extra_Time__c' => 'Extra time requested',
            'Event_Date_and_Start_Time__c' => 'Date or time moved',
            'Laser_Tag__c' => 'Laser tag added or changed',
            'Requested_Early_Closure__c' => 'Early closure requested',
            'Additional_Activity_Room__c' => 'Second room added or changed',
            'Pizza_or_Add_on_Preferences__c' => 'Add-ons changed',
            'Billing_Contact__c' => 'Billing contact changed'
        };
        Datetime f = startOf(today.addDays(-90));
        Map<String, Integer> changes = new Map<String, Integer>();
        Map<String, Integer> dateReasons = new Map<String, Integer>();
        Map<String, Integer> cancelReasons = new Map<String, Integer>();
        Set<String> fields = new Set<String>(labels.keySet());
        fields.add('Reason_for_Date_Time_Change__c');
        fields.add('Reason_for_Cancellation__c');
        for (OpportunityFieldHistory h : [
            SELECT Field, OldValue, NewValue FROM OpportunityFieldHistory
            WHERE Field IN :fields AND Opportunity.Booking_Type__c = 'Party' AND CreatedDate >= :f
            WITH USER_MODE LIMIT 10000
        ]) {
            if (h.Field == 'Reason_for_Date_Time_Change__c') {
                bump(dateReasons, h.NewValue == null ? 'Not recorded' : String.valueOf(h.NewValue));
            } else if (h.Field == 'Reason_for_Cancellation__c') {
                bump(cancelReasons, h.NewValue == null ? 'Not recorded' : String.valueOf(h.NewValue));
            } else if (h.OldValue != null) {
                bump(changes, labels.get(h.Field));
            }
        }
        w.bookingChangesLast90Days = sorted(changes);
        w.dateChangeReasonsLast90Days = sorted(dateReasons);
        w.cancellationReasonsLast90Days = sorted(cancelReasons);
    }

    private static void bump(Map<String, Integer> m, String k) {
        m.put(k, (m.containsKey(k) ? m.get(k) : 0) + 1);
    }

    private static List<Count> sorted(Map<String, Integer> m) {
        List<Count> out = new List<Count>();
        List<String> keys = new List<String>(m.keySet());
        keys.sort();
        for (String k : keys) { out.add(new Count(k, m.get(k))); }
        // simple insertion sort by count, descending (lists are short)
        for (Integer i = 1; i < out.size(); i++) {
            Count c = out[i];
            Integer j = i - 1;
            while (j >= 0 && out[j].count < c.count) { out[j + 1] = out[j]; j--; }
            out[j + 1] = c;
        }
        return out;
    }
}
