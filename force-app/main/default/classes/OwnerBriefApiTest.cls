@IsTest
private class OwnerBriefApiTest {
    @IsTest
    static void briefReportsSyncProblemsAndSpend() {
        insert new CommunityOS_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Square_Sync_Status__c = 'Failed on page 1: Square returned 401. Nothing changed.', Monthly_AI_Budget_USD__c = 1);
        AI_Call_Log__c log = new AI_Call_Log__c(Model__c = 'claude-sonnet-5', Status__c = 'Success', Est_Cost_USD__c = 0.9);
        insert log;
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        OwnerBriefApi.Brief b = OwnerBriefApi.get();
        System.assertEquals(String.valueOf(Date.today()), b.forDate);
        System.assertEquals(0.90, b.aiCostThisMonth);
        System.assert(b.needsAttention);
        System.assertEquals(2, b.attention.size(), String.valueOf(b.attention));
        String json = JSON.serialize(b);
        System.assert(!json.contains('@') , 'No contact details in the brief');
    }

    @IsTest
    static void briefComparesWithNormalAndFlagsParties() {
        Account acc = new Account(Name = 'Brieftest Household');
        insert acc;
        Date today = Date.today();
        Datetime noon = Datetime.newInstance(today, Time.newInstance(12, 0, 0, 0));
        insert new List<Visit__c>{
            new Visit__c(Square_Order_Id__c = 'BRIEF-1', Visited_At__c = noon.addDays(-1), Amount__c = 30, Counts_As_Visit__c = true),
            new Visit__c(Square_Order_Id__c = 'BRIEF-2', Visited_At__c = noon.addDays(-8), Amount__c = 20, Counts_As_Visit__c = true),
            new Visit__c(Square_Order_Id__c = 'BRIEF-3', Visited_At__c = noon.addDays(-29), Amount__c = 20, Counts_As_Visit__c = true),
            new Visit__c(Square_Order_Id__c = 'BRIEF-4', Visited_At__c = noon.addDays(-1), Amount__c = 99, Counts_As_Visit__c = false)
        };
        insert new List<Opportunity>{
            new Opportunity(AccountId = acc.Id, Name = 'Brieftest soon', StageName = 'Needs Analysis',
                CloseDate = today.addDays(1), Event_Date_and_Start_Time__c = noon.addDays(1),
                Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General'),
            new Opportunity(Name = 'Brieftest last year', StageName = 'Closed Won',
                AccountId = [SELECT Id FROM Account WHERE Name = 'Brieftest Household'].Id,
                CloseDate = today.addDays(-350), Event_Date_and_Start_Time__c = noon.addDays(-350),
                Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General')
        };
        Account other = new Account(Name = 'Brieftest Lapsed');
        insert other;
        insert new Opportunity(AccountId = other.Id, Name = 'Brieftest lapsed party', StageName = 'Closed Won',
            CloseDate = today.addDays(-340), Event_Date_and_Start_Time__c = noon.addDays(-340),
            Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General');

        OwnerBriefApi.Brief b = OwnerBriefApi.build(today);

        System.assertEquals(1, b.dropInsYesterday, 'Only visits that count as visits');
        System.assertEquals(30.00, b.dropInSpendYesterday);
        System.assertEquals(0.5, b.dropInsSameWeekdayAvg4w, 'Two of the four previous same weekdays had one visit');
        System.assertEquals(1, b.dropInsLast7Days);
        System.assertEquals(1, b.dropInsPrior7Days);
        System.assertEquals(1, b.partiesNext2DaysNotConfirmed);
        System.assertEquals(1, b.partiesNext7DaysNotConfirmed);
        System.assertEquals(1, b.openPartyEnquiries);
        System.assertEquals(0, b.oldestOpenEnquiryDays);
        System.assertEquals(1, b.rebookingCandidatesNext30Days, 'The household with an open booking is not a candidate');
        System.assertNotEquals(null, b.yesterdayWeekday);
        System.assert(!JSON.serialize(b).contains('Brieftest Household'), 'No household names in the brief');
    }
}
