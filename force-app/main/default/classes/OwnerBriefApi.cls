/**
 * Read-only morning brief for the owner, called by the n8n "Daily owner brief" workflow.
 * GET /services/apexrest/communityos/brief
 * Returns counts and today's parties only. No contact details, no children's data.
 */
@RestResource(urlMapping='/communityos/brief')
global with sharing class OwnerBriefApi {
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
        if (b.squareSyncStatus != null && !b.squareSyncStatus.startsWith('OK')) {
            b.attention.add('Square visit sync: ' + b.squareSyncStatus);
        }
        if (b.aiMonthlyBudget != null && b.aiCostThisMonth >= b.aiMonthlyBudget * 0.8) {
            b.attention.add('AI spend is at $' + b.aiCostThisMonth + ' of the $' + b.aiMonthlyBudget + ' monthly budget');
        }
        b.needsAttention = !b.attention.isEmpty();
        return b;
    }
}
