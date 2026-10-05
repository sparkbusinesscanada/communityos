@IsTest
private class Family360ControllerTest {
    private class StubLlm implements LlmClient {
        String body;
        StubLlm(String body) { this.body = body; }
        public String complete(String systemPrompt, String contextJson) { return body; }
        public String modelName() { return 'stub'; }
        public String complete(String systemPrompt, String contextJson, Map<String, Object> schema) { return body; }
        public Map<String, Integer> lastUsage() { return new Map<String, Integer>{ 'inputTokens' => 1200, 'outputTokens' => 300, 'retries' => 0, 'schemaEnforced' => 1 }; }
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
        Account acc = new Account(Name = 'Qztest Household', Phone = '6045550142');
        insert acc;
        insert new Contact(AccountId = acc.Id, FirstName = 'Anna', LastName = 'Qztest', Email = 'anna.qztest@example.com');
        insert new Opportunity(
            AccountId = acc.Id, Name = 'Qztest party', StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-340), Event_Date_and_Start_Time__c = Datetime.now().addDays(-340),
            Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General'
        );
    }

    private static Id accountId() {
        return [SELECT Id FROM Account WHERE Name = 'Qztest Household' LIMIT 1].Id;
    }

    @IsTest
    static void searchFindsOpenLeads() {
        Lead l = new Lead(FirstName = 'Searchy', LastName = 'Leadtest', Company = 'Leadtest', Phone = '6045550177', LeadSource = 'Walk-in');
        insert l;
        Test.setFixedSearchResults(new List<Id>{ l.Id });
        List<Family360Controller.HouseholdHit> hits = Family360Controller.searchHouseholds('Leadtest');
        Boolean found = false;
        for (Family360Controller.HouseholdHit h : hits) {
            if (h.kind == 'Lead' && h.leadId == l.Id) { found = true; }
        }
        System.assert(found, 'Open lead appears in search');
    }

    @IsTest
    static void searchFindsHouseholdByPhone() {
        Id aid = accountId();
        Test.setFixedSearchResults(new List<Id>{ aid });
        List<Family360Controller.HouseholdHit> hits = Family360Controller.searchHouseholds('604 555 0142');
        System.assertEquals(1, hits.size());
        System.assertEquals(aid, hits[0].accountId);
        System.assert(hits[0].people.contains('Anna'));
        System.assertEquals(0, Family360Controller.searchHouseholds('ab').size(), 'Short terms are ignored');
    }

    @IsTest
    static void householdViewAndActions() {
        Id aid = accountId();
        Family360Controller.Household h = Family360Controller.getHousehold(aid);
        System.assertEquals(1, h.people.size());
        System.assertEquals(1, h.bookings.size());
        System.assertNotEquals(null, h.primaryContactId);

        FamilyInsightService.InsightResult ins = Family360Controller.getInsights(aid);
        System.assert(ins.ok, ins.error);
        System.assertEquals(1, ins.suggestedTasks.size(), 'Mock should suggest the rebooking call');
        FamilyInsightService.SuggestedTask t = ins.suggestedTasks[0];

        Id taskId = Family360Controller.createTask(aid, t.subject, t.reason, t.dueInDays, t.relatedRecordId, ins.logId);
        Task created = [SELECT WhatId, WhoId, AI_Generated__c, AI_Call_Log__c FROM Task WHERE Id = :taskId];
        System.assertEquals(t.relatedRecordId, created.WhatId, 'Task should hang off the booking the AI cited');
        System.assert(created.AI_Generated__c);
        System.assertEquals(1, [SELECT Tasks_Created__c FROM AI_Call_Log__c WHERE Id = :ins.logId].Tasks_Created__c);

        Family360Controller.addNote(aid, null, 'Asked about <b>face painting</b>', null);
        h = Family360Controller.getHousehold(aid);
        System.assertEquals(1, h.notes.size());
        System.assert(h.notes[0].body.contains('face painting'));
        System.assertEquals(1, h.openTasks.size());
        System.assertEquals('AI', h.openTasks[0].badge);
    }

    @IsTest
    static void guardrailDropsInventedRecordsAndCapsTasks() {
        LlmClientFactory.overrideClient = new StubLlm(
            'Here you go: {"summary":"Loyal family.","insights":[],"suggestedTasks":[' +
            '{"subject":"A","dueInDays":99,"reason":"r","relatedToken":"Booking 1"},' +
            '{"subject":"B","dueInDays":1,"reason":"r","relatedToken":"Booking 7"},' +
            '{"subject":"C","dueInDays":1,"reason":"r","relatedToken":"Household"},' +
            '{"subject":"D","dueInDays":1,"reason":"r","relatedToken":"Person A"},' +
            '{"subject":"E","dueInDays":1,"reason":"r","relatedToken":"Household"}]}'
        );
        FamilyInsightService.InsightResult r = FamilyInsightService.run(accountId());
        System.assert(r.ok);
        System.assertEquals(3, r.suggestedTasks.size());
        System.assertEquals(30, r.suggestedTasks[0].dueInDays, 'Due date clamped to 30 days');
        System.assertEquals(2, r.droppedReasons.size(), 'One invented record + one over the limit');
        System.assertEquals('Filtered', [SELECT Status__c FROM AI_Call_Log__c WHERE Id = :r.logId].Status__c);
    }

    @IsTest
    static void guardrailBlocksContactDetailsAndBadJson() {
        LlmClientFactory.overrideClient = new StubLlm('{"summary":"Call her at 604-555-0142","insights":[],"suggestedTasks":[]}');
        FamilyInsightService.InsightResult r = FamilyInsightService.run(accountId());
        System.assert(!r.ok);
        System.assert(r.error.contains('contact details'));

        LlmClientFactory.overrideClient = new StubLlm('Sorry, I cannot help with that.');
        r = FamilyInsightService.run(accountId());
        System.assert(!r.ok);
        System.assertEquals(2, [SELECT COUNT() FROM AI_Call_Log__c WHERE Status__c = 'Error']);
    }

    @IsTest
    static void deferredLogsAreNotInserted() {
        List<AI_Call_Log__c> logs = new List<AI_Call_Log__c>();
        FamilyInsightService.run(accountId(), logs);
        System.assertEquals(1, logs.size());
        System.assertEquals(null, logs[0].Id);
        System.assertEquals(0, [SELECT COUNT() FROM AI_Call_Log__c]);
    }

    @IsTest
    static void emptyNoteIsRejected() {
        try {
            Family360Controller.addNote(accountId(), null, '  ', null);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
