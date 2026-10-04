@IsTest
private class ProfileServiceTest {
    private class SquareMock implements HttpCalloutMock {
        Integer status;
        SquareMock(Integer status) { this.status = status; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            String now = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            res.setBody(status == 200
                ? '{"orders":[{"closed_at":"' + now + '","total_money":{"amount":5500,"currency":"CAD"}},{"closed_at":"' + now + '","total_money":{"amount":2000,"currency":"CAD"}}]}'
                : '{"errors":[{"code":"UNAUTHORIZED"}]}');
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
        Test.setMock(HttpCalloutMock.class, new SquareMock(200));
        Account acc = new Account(Name = 'Proftest Household');
        insert acc;
        Account sq = new Account(Name = 'Sqtest Household');
        insert sq;
        insert new CommunityOS_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Square_Location_Id__c = 'LOC1');
        insert new Contact(AccountId = sq.Id, LastName = 'Sqtest', Square_Id__c = 'SQCUST1');
    }

    private static Id accountId() {
        return [SELECT Id FROM Account WHERE Name = 'Proftest Household' LIMIT 1].Id;
    }

    @IsTest
    static void unknownProfileIsAskedThenSegmented() {
        Family360Controller.Household h = Family360Controller.getHousehold(accountId());
        System.assertEquals(4, h.profile.unanswered, 'All four profile questions are open for a new family');
        System.assert(h.profile.segments.contains('New family'));

        ProfileService.ProfileInput p = new ProfileService.ProfileInput();
        p.visitFrequency = 'Monthly';
        p.heardAbout = 'School or daycare';
        p.interests = new List<String>{ 'Camps and classes', 'Laser tag' };
        p.preferredContact = 'Text message';
        p.schoolDaycare = 'Maple Elementary';
        Family360Controller.saveProfile(accountId(), JSON.serialize(p));

        Account a = [SELECT Segment__c, Profile_Updated__c, Interests__c FROM Account WHERE Id = :accountId()];
        System.assert(a.Segment__c.contains('Camp family'), a.Segment__c);
        System.assert(a.Segment__c.contains('Regular visitor'), a.Segment__c);
        System.assert(a.Segment__c.contains('School / daycare link'), a.Segment__c);
        System.assertEquals(Date.today(), a.Profile_Updated__c);
        System.assertEquals(0, Family360Controller.getHousehold(accountId()).profile.unanswered);
    }

    @IsTest
    static void lapsedAndRepeatPartySegments() {
        ProfileService.Signals sig = new ProfileService.Signals();
        sig.partiesHosted = 3;
        sig.lastActivity = Date.today().addDays(-400);
        sig.customerSince = Date.today().addDays(-900);
        List<String> seg = ProfileService.segmentsFor(null, new List<String>(), null, sig);
        System.assert(seg.contains('Repeat party family'));
        System.assert(seg.contains('Lapsed'));
    }

    @IsTest
    static void visitSummaryLiveAndFallback() {
        Id sqAccount = [SELECT Id FROM Account WHERE Name = 'Sqtest Household' LIMIT 1].Id;
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE AccountId = :sqAccount AND Square_Id__c != null], 'Square id kept on insert');
        Test.setMock(HttpCalloutMock.class, new SquareMock(200));
        Test.startTest();
        VisitSummaryService.Summary live = Family360Controller.getVisitSummary(sqAccount);
        System.assertEquals(null, live.note, 'Live Square answered');
        System.assertEquals('Square (live)', live.source);
        System.assertEquals(2, live.visitsThisYear);
        System.assertEquals(75, live.spend12Months);
        Test.setMock(HttpCalloutMock.class, new SquareMock(401));
        VisitSummaryService.Summary fallback = VisitSummaryService.get(sqAccount);
        Test.stopTest();
        System.assert(fallback.source.startsWith('Salesforce'));
        System.assertNotEquals(null, fallback.note);
    }
}
