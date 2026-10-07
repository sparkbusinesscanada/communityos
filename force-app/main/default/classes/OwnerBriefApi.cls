/**
 * Read-only morning brief for the owner, called by the n8n "Daily owner brief" workflow.
 * GET /services/apexrest/communityos/brief
 * Returns counts, trends and today's parties only. No contact details, no children's data.
 *
 * Everything here is deterministic: the same records always give the same numbers.
 * n8n applies fixed rules to these numbers, and only then asks Claude to read them.
 */
@RestResource(urlMapping='/communityos/brief')
global with sharing class OwnerBriefApi {
    public static final Set<String> CONFIRMED_STAGES = new Set<String>{
        'Invoice Paid / Party Confirmed', 'Confirmation Call Completed', 'Closed Won'
    };
    public static final Set<String> ENQUIRY_STAGES = new Set<String>{ 'Prospecting', 'Needs Analysis' };

    global class Party {
        public String timeLabel;
        public String booking;
        public String room;
        public String packageName;
        public Decimal kids;
        public String stage;
    }

    global class Brief {
        public String forDate;
        public List<Party> partiesToday = new List<Party>();
        public Integer partiesNext7Days = 0;
        public Integer unpaidOrders = 0;
        public Decimal unpaidTotal = 0;
        public Integer rebookingTasksDueToday = 0;
        public Integer openTasksDueToday = 0;
        public Integer visitsYesterday = 0;
        public Integer visitsYesterdayLinked = 0;
        public Decimal squareSpendYesterday = 0;
        public String squareSyncStatus;
        public String squareLastSync;
        public Integer aiCallsYesterday = 0;
        public Decimal aiCostYesterday = 0;
        public Decimal aiCostThisMonth = 0;
        public Decimal aiMonthlyBudget;
        public Boolean needsAttention = false;
        public List<String> attention = new List<String>();

        // Trends: drop-in visits (Counts_As_Visit__c) compared with normal
        public String yesterdayWeekday;
        public Integer dropInsYesterday = 0;
        public Decimal dropInSpendYesterday = 0;
        public Decimal dropInsSameWeekdayAvg4w = 0;
        public Decimal dropInSpendSameWeekdayAvg4w = 0;
        public Integer dropInsLast7Days = 0;
        public Integer dropInsPrior7Days = 0;
        public Decimal dropInSpendLast7Days = 0;
        public Decimal dropInSpendPrior7Days = 0;
        // Parties
        public Integer partiesNext2DaysNotConfirmed = 0;
        public Integer partiesNext7DaysNotConfirmed = 0;
        public Integer partyBookingsLast7Days = 0;
        public Integer partyBookingsPrior7Days = 0;
        public Integer openPartyEnquiries = 0;
        public Integer oldestOpenEnquiryDays;
        public Integer rebookingCandidatesNext30Days = 0;
        // Money owed, by age of the order
        public Integer unpaidUpTo7Days = 0;
        public Integer unpaid8To30Days = 0;
        public Integer unpaidOver30Days = 0;
        public Decimal unpaidOver30DaysTotal = 0;
    }

    @HttpGet
    global static Brief get() {
        return build(Date.today());
    }

    public static Brief build(Date today) {
        Brief b = new Brief();
        b.forDate = String.valueOf(today);
        for (Opportunity o : [
            SELECT Name, StageName, Activity_Room__c, Party_Package__c, Estimated_Children__c, Event_Date_and_Start_Time__c
            FROM Opportunity
            WHERE Booking_Type__c = 'Party' AND StageName != 'Closed Lost' AND Event_Date_and_Start_Time__c = TODAY
            WITH USER_MODE ORDER BY Event_Date_and_Start_Time__c LIMIT 50
        ]) {
            Party p = new Party();
            p.timeLabel = o.Event_Date_and_Start_Time__c.format('h:mm a');
            p.booking = o.Name;
            p.room = o.Activity_Room__c;
            p.packageName = o.Party_Package__c;
            p.kids = o.Estimated_Children__c;
            p.stage = o.StageName;
            b.partiesToday.add(p);
        }
        b.partiesNext7Days = [SELECT COUNT() FROM Opportunity WHERE Booking_Type__c = 'Party' AND StageName != 'Closed Lost' AND Event_Date_and_Start_Time__c = NEXT_N_DAYS:7 WITH USER_MODE];
        for (AggregateResult ar : [SELECT COUNT(Id) n, SUM(Total_Amount_with_Taxes__c) t FROM Order WHERE Invoice_Status__c IN ('UNPAID', 'FAILED') AND EffectiveDate <= TODAY WITH USER_MODE]) {
            b.unpaidOrders = (Integer) ar.get('n');
            b.unpaidTotal = ar.get('t') == null ? 0 : (Decimal) ar.get('t');
        }
        b.rebookingTasksDueToday = [SELECT COUNT() FROM Task WHERE IsClosed = false AND ActivityDate = TODAY AND Subject LIKE :(RebookingReminderJob.SUBJECT_PREFIX + '%') WITH USER_MODE];
        b.openTasksDueToday = [SELECT COUNT() FROM Task WHERE IsClosed = false AND ActivityDate <= TODAY WITH USER_MODE];
        for (AggregateResult ar : [SELECT COUNT(Id) n, COUNT(Household__c) h, SUM(Amount__c) s FROM Visit__c WHERE Visited_At__c = YESTERDAY WITH USER_MODE]) {
            b.visitsYesterday = (Integer) ar.get('n');
            b.visitsYesterdayLinked = (Integer) ar.get('h');
            b.squareSpendYesterday = ar.get('s') == null ? 0 : (Decimal) ar.get('s');
        }
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
        if (s != null) {
            b.squareSyncStatus = s.Square_Sync_Status__c;
            b.squareLastSync = s.Square_Last_Sync__c == null ? null : s.Square_Last_Sync__c.format('d MMM h:mm a');
            b.aiMonthlyBudget = s.Monthly_AI_Budget_USD__c;
        }
        for (AggregateResult ar : [SELECT COUNT(Id) n, SUM(Est_Cost_USD__c) c FROM AI_Call_Log__c WHERE CreatedDate = YESTERDAY AND (NOT Model__c LIKE 'mock%') WITH SYSTEM_MODE]) {
            b.aiCallsYesterday = (Integer) ar.get('n');
            b.aiCostYesterday = ar.get('c') == null ? 0 : ((Decimal) ar.get('c')).setScale(2);
        }
        for (AggregateResult ar : [SELECT SUM(Est_Cost_USD__c) c FROM AI_Call_Log__c WHERE CreatedDate = THIS_MONTH AND (NOT Model__c LIKE 'mock%') WITH SYSTEM_MODE]) {
            b.aiCostThisMonth = ar.get('c') == null ? 0 : ((Decimal) ar.get('c')).setScale(2);
        }
        addVisitTrends(b, today);
        addPartyTrends(b, today);
        addUnpaidAging(b, today);
        if (b.squareSyncStatus != null && !b.squareSyncStatus.startsWith('OK')) {
            b.attention.add('Square visit sync: ' + b.squareSyncStatus);
        }
        if (b.aiMonthlyBudget != null && b.aiCostThisMonth >= b.aiMonthlyBudget * 0.8) {
            b.attention.add('AI spend is at $' + b.aiCostThisMonth + ' of the $' + b.aiMonthlyBudget + ' monthly budget');
        }
        b.needsAttention = !b.attention.isEmpty();
        return b;
    }

    /** Drop-in visits per local day for the last 29 days, then yesterday vs the same weekday and week vs week. */
    @TestVisible
    private static void addVisitTrends(Brief b, Date today) {
        Date yesterday = today.addDays(-1);
        b.yesterdayWeekday = Datetime.newInstance(yesterday, Time.newInstance(12, 0, 0, 0)).format('EEEE');
        Datetime fromTs = Datetime.newInstance(today.addDays(-29), Time.newInstance(0, 0, 0, 0));
        Datetime toTs = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        Map<Date, Integer> countByDay = new Map<Date, Integer>();
        Map<Date, Decimal> spendByDay = new Map<Date, Decimal>();
        for (Visit__c v : [
            SELECT Visited_At__c, Amount__c FROM Visit__c
            WHERE Counts_As_Visit__c = true AND Visited_At__c >= :fromTs AND Visited_At__c < :toTs
            WITH USER_MODE LIMIT 20000
        ]) {
            Date d = v.Visited_At__c.date();
            countByDay.put(d, (countByDay.containsKey(d) ? countByDay.get(d) : 0) + 1);
            spendByDay.put(d, (spendByDay.containsKey(d) ? spendByDay.get(d) : 0) + (v.Amount__c == null ? 0 : v.Amount__c));
        }
        Integer weekdayCount = 0;
        Decimal weekdaySpend = 0;
        for (Integer offset = 1; offset <= 28; offset++) {
            Date d = today.addDays(-offset);
            Integer n = countByDay.containsKey(d) ? countByDay.get(d) : 0;
            Decimal amt = spendByDay.containsKey(d) ? spendByDay.get(d) : 0;
            if (offset == 1) {
                b.dropInsYesterday = n;
                b.dropInSpendYesterday = amt;
            } else if (Math.mod(offset - 1, 7) == 0) {
                weekdayCount += n;
                weekdaySpend += amt;
            }
            if (offset <= 7) {
                b.dropInsLast7Days += n;
                b.dropInSpendLast7Days += amt;
            } else if (offset <= 14) {
                b.dropInsPrior7Days += n;
                b.dropInSpendPrior7Days += amt;
            }
        }
        // offsets 8, 15, 22 and 29 are the four previous same weekdays; 29 is outside the loop above
        Date fourthWeek = today.addDays(-29);
        weekdayCount += countByDay.containsKey(fourthWeek) ? countByDay.get(fourthWeek) : 0;
        weekdaySpend += spendByDay.containsKey(fourthWeek) ? spendByDay.get(fourthWeek) : 0;
        b.dropInsSameWeekdayAvg4w = (Decimal.valueOf(weekdayCount) / 4).setScale(1);
        b.dropInSpendSameWeekdayAvg4w = (weekdaySpend / 4).setScale(2);
        b.dropInSpendYesterday = b.dropInSpendYesterday.setScale(2);
        b.dropInSpendLast7Days = b.dropInSpendLast7Days.setScale(2);
        b.dropInSpendPrior7Days = b.dropInSpendPrior7Days.setScale(2);
    }

    @TestVisible
    private static void addPartyTrends(Brief b, Date today) {
        Datetime startToday = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        Datetime in2Days = startToday.addDays(2);
        Datetime in7Days = startToday.addDays(7);
        for (Opportunity o : [
            SELECT StageName, Event_Date_and_Start_Time__c FROM Opportunity
            WHERE Booking_Type__c = 'Party' AND StageName != 'Closed Lost'
              AND Event_Date_and_Start_Time__c >= :startToday AND Event_Date_and_Start_Time__c < :in7Days
            WITH USER_MODE LIMIT 500
        ]) {
            if (!CONFIRMED_STAGES.contains(o.StageName)) {
                b.partiesNext7DaysNotConfirmed++;
                if (o.Event_Date_and_Start_Time__c < in2Days) {
                    b.partiesNext2DaysNotConfirmed++;
                }
            }
        }
        Datetime d7 = startToday.addDays(-7);
        Datetime d14 = startToday.addDays(-14);
        b.partyBookingsLast7Days = [SELECT COUNT() FROM Opportunity WHERE Booking_Type__c = 'Party' AND StageName != 'Closed Lost' AND CreatedDate >= :d7 AND CreatedDate < :startToday WITH USER_MODE];
        b.partyBookingsPrior7Days = [SELECT COUNT() FROM Opportunity WHERE Booking_Type__c = 'Party' AND StageName != 'Closed Lost' AND CreatedDate >= :d14 AND CreatedDate < :d7 WITH USER_MODE];
        for (Opportunity o : [
            SELECT CreatedDate FROM Opportunity
            WHERE Booking_Type__c = 'Party' AND StageName IN :ENQUIRY_STAGES
              AND (Event_Date_and_Start_Time__c = null OR Event_Date_and_Start_Time__c >= :startToday)
            WITH USER_MODE ORDER BY CreatedDate ASC LIMIT 500
        ]) {
            b.openPartyEnquiries++;
            if (b.oldestOpenEnquiryDays == null) {
                b.oldestOpenEnquiryDays = o.CreatedDate.date().daysBetween(today);
            }
        }
        // Families whose party was 11-12 months ago (anniversary in the next 30 days) with nothing booked ahead
        Datetime yearAgo = startToday.addDays(-365);
        Datetime elevenMonthsAgo = startToday.addDays(-335);
        Set<Id> households = new Set<Id>();
        for (Opportunity o : [
            SELECT AccountId FROM Opportunity
            WHERE IsWon = true AND Booking_Type__c = 'Party' AND AccountId != null
              AND Event_Date_and_Start_Time__c >= :yearAgo AND Event_Date_and_Start_Time__c < :elevenMonthsAgo
            WITH USER_MODE LIMIT 2000
        ]) {
            households.add(o.AccountId);
        }
        if (!households.isEmpty()) {
            for (Opportunity f : [
                SELECT AccountId FROM Opportunity
                WHERE AccountId IN :households AND StageName != 'Closed Lost'
                  AND (IsClosed = false OR Event_Date_and_Start_Time__c >= :startToday)
                WITH USER_MODE LIMIT 2000
            ]) {
                households.remove(f.AccountId);
            }
        }
        b.rebookingCandidatesNext30Days = households.size();
    }

    @TestVisible
    private static void addUnpaidAging(Brief b, Date today) {
        for (Order o : [
            SELECT EffectiveDate, Total_Amount_with_Taxes__c FROM Order
            WHERE Invoice_Status__c IN ('UNPAID', 'FAILED') AND EffectiveDate <= :today
            WITH USER_MODE LIMIT 2000
        ]) {
            Integer age = o.EffectiveDate.daysBetween(today);
            if (age <= 7) { b.unpaidUpTo7Days++; }
            else if (age <= 30) { b.unpaid8To30Days++; }
            else { b.unpaidOver30Days++; b.unpaidOver30DaysTotal += o.Total_Amount_with_Taxes__c == null ? 0 : o.Total_Amount_with_Taxes__c; }
        }
        b.unpaidOver30DaysTotal = b.unpaidOver30DaysTotal.setScale(2);
    }
}
