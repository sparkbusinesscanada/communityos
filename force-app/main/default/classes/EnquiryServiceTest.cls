@IsTest
private class EnquiryServiceTest {
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
        Account acc = new Account(Name = 'Enqtest Household', Phone = '6045550177');
        insert acc;
        insert new Contact(AccountId = acc.Id, FirstName = 'Eve', LastName = 'Enqtest', Email = 'eve.enqtest@example.com');
        insert new Opportunity(
            AccountId = acc.Id, Name = 'Enqtest party', StageName = 'Closed Won',
            CloseDate = Date.today().addDays(30), Event_Date_and_Start_Time__c = Datetime.newInstance(Date.today().addDays(30), Time.newInstance(14, 0, 0, 0)),
            Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General'
        );
    }

    private static Id accountId() {
        return [SELECT Id FROM Account WHERE Name = 'Enqtest Household' LIMIT 1].Id;
    }

    private static Id bookingId() {
        return [SELECT Id FROM Opportunity WHERE Account.Name = 'Enqtest Household' LIMIT 1].Id;
    }

    private static EnquiryService.EnquiryInput newParty() {
        EnquiryService.EnquiryInput i = new EnquiryService.EnquiryInput();
        i.enquiryType = EnquiryService.NEW_PARTY;
        i.channel = 'Phone';
        i.preferredDate = Date.today().addDays(40);
        i.backupDate = Date.today().addDays(47);
        i.kids = 18;
        i.adults = 10;
        i.pizzas = 6;
        i.addOns = new List<String>{ 'Face painting', 'Balloon art' };
        i.allergyFlagged = true;
        i.notes = 'Wants the underwater room. Eve says her son has a nut allergy.';
        i.followUpDate = Date.today().addDays(2);
        return i;
    }

    @IsTest
    static void optionsComeFromPicklists() {
        EnquiryService.Options o = Family360Controller.getEnquiryOptions();
        System.assertEquals(6, o.intents.size());
        System.assert(!o.packages.isEmpty());
        System.assert(!o.times.isEmpty());
        System.assert(!o.cancelReasons.isEmpty());
        System.assert(!o.interests.isEmpty());
    }

    @IsTest
    static void newPartyDraftCreatesLeadWhenEmailIsOff() {
        EnquiryService.emailOffOverride = true;
        EnquiryService.liveWritesOverride = false;
        EnquiryService.Draft d = Family360Controller.saveEnquiry(accountId(), JSON.serialize(newParty()));
        System.assertEquals('Lead', d.target);
        System.assert(d.canApply, d.blockedReason);
        System.assertEquals(1, [SELECT COUNT() FROM Team_notes__c], 'What they said becomes a staff note');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :d.enquiryId], 'Follow-up task');

        EnquiryService.Draft applied = Family360Controller.applyEnquiry(d.enquiryId);
        System.assertEquals('Applied', applied.status);
        Lead l = [SELECT LastName, Company, Number_of_Kids__c, Preferred_Date__c, Facepainter__c, Pizza_Preference__c, LeadSource FROM Lead WHERE Id = :applied.appliedRecordId];
        System.assertEquals(18, l.Number_of_Kids__c);
        System.assertEquals('Yes', l.Facepainter__c);
        System.assertEquals('Phone', l.LeadSource);
        System.assert(l.Pizza_Preference__c.contains('6 pizzas'));
        try {
            EnquiryService.apply(d.enquiryId);
            System.assert(false, 'Second apply must fail');
        } catch (EnquiryService.EnquiryException e) {
            System.assert(e.getMessage().contains('already'));
        }
    }

    @IsTest
    static void leadHeldWhenEmailsWouldSend() {
        EnquiryService.emailOffOverride = false;
        EnquiryService.liveWritesOverride = false;
        EnquiryService.Draft d = EnquiryService.save(accountId(), newParty());
        System.assert(!d.canApply);
        System.assert(d.blockedReason.startsWith('Sandbox'));
        EnquiryService.Draft held = EnquiryService.apply(d.enquiryId);
        System.assertEquals('Held in sandbox', held.status);
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Company = 'Enqtest Household']);
    }

    @IsTest
    static void bookingChangeHeldInSandboxAppliedWhenLive() {
        EnquiryService.EnquiryInput i = new EnquiryService.EnquiryInput();
        i.enquiryType = EnquiryService.CHANGE_BOOKING;
        i.bookingId = bookingId();
        i.changes = new List<String>{ 'Headcount', 'Room' };
        i.kids = 22;
        i.adults = 12;
        i.roomPreference = 'Underwater';

        EnquiryService.liveWritesOverride = false;
        EnquiryService.Draft d = EnquiryService.save(accountId(), i);
        System.assertEquals('Booking', d.target);
        System.assert(!d.canApply, 'Booking changes sync to Square, so they are held in the sandbox');

        EnquiryService.liveWritesOverride = true;
        EnquiryService.Draft applied = EnquiryService.apply(d.enquiryId);
        System.assertEquals('Applied', applied.status);
        Opportunity o = [SELECT Estimated_Children__c, Activity_Room__c FROM Opportunity WHERE Id = :bookingId()];
        System.assertEquals(22, o.Estimated_Children__c);
        System.assertEquals('Underwater', o.Activity_Room__c);
    }

    @IsTest
    static void ordersAndQuestionsAreNotWritten() {
        EnquiryService.EnquiryInput i = new EnquiryService.EnquiryInput();
        i.enquiryType = EnquiryService.LASER_TAG;
        i.preferredDate = Date.today().addDays(3);
        i.players = 8;
        i.laserPackage = '2 Game';
        EnquiryService.Draft d = EnquiryService.save(accountId(), i);
        System.assertEquals('Order', d.target);
        System.assert(!d.canApply);

        EnquiryService.EnquiryInput q = new EnquiryService.EnquiryInput();
        q.enquiryType = EnquiryService.QUESTION;
        q.notes = 'Asked about holiday hours.';
        EnquiryService.Draft n = EnquiryService.save(accountId(), q);
        System.assertEquals('Staff note', n.target);
        System.assertEquals('Note only', n.status);

        EnquiryService.discard(d.enquiryId);
        System.assertEquals('Discarded', [SELECT Draft_Status__c FROM Family_Enquiry__c WHERE Id = :d.enquiryId].Draft_Status__c);
        System.assertEquals(2, Family360Controller.getHousehold(accountId()).enquiries.size());
    }

    @IsTest
    static void rejectsBadInput() {
        List<EnquiryService.EnquiryInput> bad = new List<EnquiryService.EnquiryInput>();
        EnquiryService.EnquiryInput a = newParty();
        a.kids = -1;
        bad.add(a);
        EnquiryService.EnquiryInput b = newParty();
        b.preferredDate = Date.today().addDays(-1);
        bad.add(b);
        EnquiryService.EnquiryInput c = newParty();
        c.enquiryType = null;
        bad.add(c);
        EnquiryService.EnquiryInput d = newParty();
        d.preferredDate = null;
        bad.add(d);
        EnquiryService.EnquiryInput e = new EnquiryService.EnquiryInput();
        e.enquiryType = EnquiryService.CHANGE_BOOKING;
        bad.add(e);
        for (EnquiryService.EnquiryInput i : bad) {
            try {
                Family360Controller.saveEnquiry(accountId(), JSON.serialize(i));
                System.assert(false, 'Expected error for ' + JSON.serialize(i));
            } catch (AuraHandledException ex) {
                System.assert(true);
            }
        }
    }

    @IsTest
    static void enquiryReachesAiContextWithoutHealthData() {
        EnquiryService.emailOffOverride = true;
        EnquiryService.save(accountId(), newParty());
        String json = FamilyContextBuilder.build(accountId()).contextJson;
        System.assert(json.contains('Enquiry 1'), json);
        System.assert(json.contains('underwater room'), json);
        System.assert(!json.containsIgnoreCase('allerg'), 'Allergy text and flag never reach the AI');
    }

    @IsTest
    static void typedQuestionIsAnsweredAndSaved() {
        DeskAgentService.DeskResult r = Family360Controller.askDesk(accountId(), new List<String>(), 'Do they have any camp history?', null);
        System.assert(r.ok, r.error);
        System.assertEquals(DeskAgentService.CUSTOM_KEY, [SELECT Question_Key__c FROM Desk_Question__c WHERE Id = :r.answers[0].deskQuestionId].Question_Key__c);
        System.assert(!Family360Controller.askDesk(accountId(), new List<String>(), '  ', null).ok);
    }
}
