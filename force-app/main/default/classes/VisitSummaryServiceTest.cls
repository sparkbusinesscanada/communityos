@IsTest
private class VisitSummaryServiceTest {
    @TestSetup
    static void setup() {
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'CommunityOS_Family360' LIMIT 1].Id;
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :psId] == 0) {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = psId);
            }
        }
        insert new CommunityOS_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Square_Location_Id__c = 'LOC1');
        Account acc = new Account(Name = 'Visitsync Household');
        insert acc;
        insert new Contact(AccountId = acc.Id, LastName = 'Visitsync', Square_Id__c = 'SQC1');
    }

    @IsTest
    static void summaryAndSegmentsUseVisits() {
        SquareVisitSync.ingest(SquareVisitSyncTest.sampleBody());
        Id accId = [SELECT Id FROM Account WHERE Name = 'Visitsync Household'].Id;
        VisitSummaryService.Summary s = Family360Controller.getVisitSummary(accId);
        System.assert(s.source.startsWith('Square visits'), s.source);
        System.assertEquals(2, s.visitsLast90Days, 'One visit per day');
        System.assertEquals(1111.53, s.spend12Months);
        System.assert(s.mix.contains('Party 1') && s.mix.contains('Drop-in 1'), s.mix);
        FamilyContextBuilder.Result ctx = FamilyContextBuilder.build(accId);
        String json = ctx.contextJson;
        System.assert(json.contains('squareVisits'), 'AI sees the aggregate');
        System.assert(!json.contains('ORD-PARTY') && !json.contains('Private Party'), 'AI never sees order ids or item lines');
    }

    @IsTest
    static void depositIsSpendButNotAVisit() {
        String day = Datetime.now().addDays(-5).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        SquareVisitSync.ingest('{"orders":[' + SquareVisitSyncTest.order('ORD-DEP', 'SQC1', 5500, SquareVisitSyncTest.item('$55 Non-refundable Deposit', '', '1', 5500), day) + ']}');
        Visit__c v = [SELECT Offering__c, Counts_As_Visit__c FROM Visit__c WHERE Square_Order_Id__c = 'ORD-DEP'];
        System.assertEquals('Party', v.Offering__c);
        System.assertEquals(false, v.Counts_As_Visit__c);
        Id accId = [SELECT Id FROM Account WHERE Name = 'Visitsync Household'].Id;
        VisitSummaryService.Summary s = VisitSummaryService.get(accId);
        System.assertEquals(55, s.spend12Months);
        System.assertEquals(0, s.visitsLast90Days);
        System.assertEquals(null, s.lastVisit);
    }
}
