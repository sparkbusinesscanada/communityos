@IsTest
private class DeskAgentServiceTest {
    private class StubLlm implements LlmClient {
        String body;
        StubLlm(String body) { this.body = body; }
        public String complete(String systemPrompt, String contextJson) { return body; }
        public String modelName() { return 'stub'; }
    }

    private class AnyCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'CommunityOS_Family360' LIMIT 1].Id;
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :psId] == 0) {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = psId);
            }
        }
        Test.setMock(HttpCalloutMock.class, new AnyCalloutMock());
        Account acc = new Account(Name = 'Dqtest Household');
        insert acc;
        insert new Contact(AccountId = acc.Id, FirstName = 'Dana', LastName = 'Dqtest');
        insert new Opportunity(
            AccountId = acc.Id, Name = 'Dqtest party', StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-100), Event_Date_and_Start_Time__c = Datetime.now().addDays(-100),
            Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General'
        );
    }

    private static Id accountId() {
        return [SELECT Id FROM Account WHERE Name = 'Dqtest Household' LIMIT 1].Id;
    }

    @IsTest
    static void templatesAreActiveAndOrdered() {
        List<DeskAgentService.Question> qs = DeskAgentService.templates();
        System.assert(qs.size() >= 5, 'Checklist questions are deployed as custom metadata');
        System.assertEquals('Last_Party', qs[0].key);
    }

    @IsTest
    static void mockAnswersAndRecordsAgainstBooking() {
        DeskAgentService.DeskResult r = DeskAgentService.ask(accountId(), new List<String>{ 'Last_Party', 'Camps' });
        System.assert(r.ok, r.error);
        System.assertEquals(2, r.answers.size());
        System.assertEquals(DeskAgentService.STATUS_ANSWERED, r.answers[0].status);
        System.assertEquals(DeskAgentService.STATUS_NOT_IN_RECORDS, r.answers[1].status);

        Desk_Question__c dq = [SELECT Account__c, Booking__c, Contact__c, Answer_Status__c, Source_Records__c, AI_Call_Log__c, Answered_By_Agent__c
                               FROM Desk_Question__c WHERE Id = :r.answers[0].deskQuestionId];
        System.assertEquals(accountId(), dq.Account__c);
        System.assertNotEquals(null, dq.Booking__c, 'Answer is recorded against the booking it cited');
        System.assertNotEquals(null, dq.Contact__c);
        System.assertEquals('Booking 1', dq.Source_Records__c);
        System.assert(dq.Answered_By_Agent__c);
        System.assertNotEquals(null, dq.AI_Call_Log__c);

        DeskAgentService.markOutcome(dq.Id, 'resolved');
        System.assert([SELECT Resolved_On_Spot__c FROM Desk_Question__c WHERE Id = :dq.Id].Resolved_On_Spot__c);

        Family360Controller.Household h = Family360Controller.getHousehold(accountId());
        System.assertEquals(2, h.deskHistory.size());
    }

    @IsTest
    static void answerWithoutSourceIsBlocked() {
        LlmClientFactory.overrideClient = new StubLlm(
            '{"answers":[{"key":"Last_Party","status":"answered","answer":"Last March.","sources":["Booking 9"]}]}');
        DeskAgentService.DeskResult r = DeskAgentService.ask(accountId(), new List<String>{ 'Last_Party' });
        System.assert(r.ok);
        System.assertEquals(DeskAgentService.STATUS_BLOCKED, r.answers[0].status, 'Invented source tokens are not accepted');
        System.assertEquals('Filtered', [SELECT Status__c FROM AI_Call_Log__c WHERE Id = :r.logId].Status__c);
    }

    @IsTest
    static void contactDetailsBlockWholeResponse() {
        LlmClientFactory.overrideClient = new StubLlm(
            '{"answers":[{"key":"Last_Party","status":"answered","answer":"Call 604-555-0111","sources":["Booking 1"]}]}');
        DeskAgentService.DeskResult r = Family360Controller.askDesk(accountId(), new List<String>{ 'Last_Party' });
        System.assert(!r.ok);
        System.assertEquals(0, [SELECT COUNT() FROM Desk_Question__c]);
    }

    @IsTest
    static void noTickedQuestions() {
        DeskAgentService.DeskResult r = DeskAgentService.ask(accountId(), new List<String>());
        System.assert(!r.ok);
        System.assertEquals(10, Family360Controller.getDeskQuestions().size());
    }
}
