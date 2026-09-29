@IsTest
private class RebookingReminderJobTest {
    private class AnyCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private static Opportunity party(Id accountId, Datetime eventAt, String stage) {
        return new Opportunity(
            AccountId = accountId, Name = 'Rbtest party', StageName = stage,
            CloseDate = eventAt.date(), Event_Date_and_Start_Time__c = eventAt,
            Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General'
        );
    }

    @IsTest
    static void createsOneReminderOnlyForEligibleHouseholds() {
        Test.setMock(HttpCalloutMock.class, new AnyCalloutMock());
        Date today = Date.newInstance(2026, 9, 29);
        Date anniversaryLastYear = today.addDays(RebookingReminderJob.LEAD_DAYS).addYears(-1);
        Datetime eventAt = Datetime.newInstance(anniversaryLastYear, Time.newInstance(14, 0, 0, 0));

        Account eligible = new Account(Name = 'Rbtest Eligible');
        Account alreadyBooked = new Account(Name = 'Rbtest Booked');
        insert new List<Account>{ eligible, alreadyBooked };
        insert new Contact(AccountId = eligible.Id, LastName = 'Rbtest');

        insert new List<Opportunity>{
            party(eligible.Id, eventAt, 'Closed Won'),
            party(alreadyBooked.Id, eventAt, 'Closed Won'),
            party(alreadyBooked.Id, Datetime.now().addDays(60), 'Closed Won')
        };

        Test.startTest();
        Database.executeBatch(new RebookingReminderJob(today));
        Test.stopTest();

        List<Task> tasks = [SELECT AccountId, Subject, AI_Reason__c, WhoId FROM Task WHERE Subject LIKE 'Rebooking reminder%'];
        System.assertEquals(1, tasks.size(), 'Only the household with nothing booked ahead gets a reminder');
        System.assertEquals(eligible.Id, tasks[0].AccountId);
        System.assertNotEquals(null, tasks[0].WhoId);
        System.assert(tasks[0].AI_Reason__c.contains(String.valueOf(anniversaryLastYear)));
    }

    @IsTest
    static void doesNotDuplicateReminders() {
        Test.setMock(HttpCalloutMock.class, new AnyCalloutMock());
        Date today = Date.newInstance(2026, 9, 29);
        Datetime eventAt = Datetime.newInstance(today.addDays(RebookingReminderJob.LEAD_DAYS).addYears(-1), Time.newInstance(14, 0, 0, 0));
        Account a = new Account(Name = 'Rbtest Dup');
        insert a;
        Opportunity o = party(a.Id, eventAt, 'Closed Won');
        insert o;
        insert new Task(WhatId = o.Id, Subject = RebookingReminderJob.SUBJECT_PREFIX + ': earlier', Status = 'Not Started');

        Test.startTest();
        Database.executeBatch(new RebookingReminderJob(today));
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Rebooking reminder%']);
    }

    @IsTest
    static void schedulesBatch() {
        Test.startTest();
        String jobId = System.schedule('Rbtest schedule', '0 0 6 * * ?', new RebookingReminderJob());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
