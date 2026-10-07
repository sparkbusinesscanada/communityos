@IsTest
private class OwnerWeeklyApiTest {
    @IsTest
    static void weeklyCountsFunnelSeasonsAndConversion() {
        Date today = Date.today();
        Datetime noon = Datetime.newInstance(today, Time.newInstance(12, 0, 0, 0));
        Account hh = new Account(Name = '6045550142', Phone = '6045550142');
        insert hh;
        Lead booked = new Lead(LastName = 'Weeklytest', Company = 'Household', Phone = '(604) 555-0142', LeadSource = 'Web');
        Lead notBooked = new Lead(LastName = 'Weeklytest2', Company = 'Household', Phone = '604-555-0199', Email = 'weekly@example.com', LeadSource = 'Phone');
        insert new List<Lead>{ booked, notBooked };
        Test.setCreatedDate(booked.Id, noon.addDays(-40));
        Test.setCreatedDate(notBooked.Id, noon.addDays(-40));
        Opportunity party = new Opportunity(AccountId = hh.Id, Name = 'Weeklytest party', StageName = 'Invoice Paid / Party Confirmed',
            CloseDate = today.addDays(10), Event_Date_and_Start_Time__c = noon.addDays(10),
            Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General',
            Estimated_Children__c = 12);
        Opportunity held = new Opportunity(AccountId = hh.Id, Name = 'Weeklytest held', StageName = 'Closed Won',
            CloseDate = today.addMonths(-2), Event_Date_and_Start_Time__c = noon.addMonths(-2),
            Booking_Type__c = 'Party', Event_Type__c = 'Birthday', Activity_Room__c = 'Field', Party_Package__c = 'General',
            Estimated_Children__c = 15);
        insert new List<Opportunity>{ party, held };
        Test.setCreatedDate(party.Id, noon.addDays(-35));
        Test.setCreatedDate(held.Id, noon.addMonths(-3));

        Test.startTest();
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        OwnerWeeklyApi.Weekly w = OwnerWeeklyApi.get();
        Test.stopTest();

        System.assertEquals(4, w.periods.size());
        OwnerWeeklyApi.Cohort recent = w.cohorts[0];
        System.assertEquals(2, recent.leads);
        System.assertEquals(1, recent.leadsThatBooked, 'Matched by the household phone');
        System.assertEquals(50.0, recent.conversionPct);
        System.assertEquals(24, w.months.size());
        Integer held24 = 0;
        for (OwnerWeeklyApi.Month m : w.months) { held24 += m.partiesHeld; }
        System.assertEquals(1, held24);
        System.assertEquals(1, w.partiesOnBooksNext28Days);
        String json = JSON.serialize(w);
        System.assert(!json.contains('555') && !json.contains('@') && !json.contains('Weeklytest'), 'No names or contact details');
    }

    @IsTest
    static void phoneDigitsAreNormalised() {
        System.assertEquals('6045550142', OwnerWeeklyApi.digits('+1 (604) 555-0142'));
        System.assertEquals(null, OwnerWeeklyApi.digits('555-0142'));
        System.assertEquals(null, OwnerWeeklyApi.digits(null));
    }
}
