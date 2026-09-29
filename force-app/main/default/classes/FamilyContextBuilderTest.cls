@IsTest
private class FamilyContextBuilderTest {
    private static final String PARENT_FIRST = 'Janeqz';
    private static final String FAMILY_LAST = 'Testfamilyqz';
    private static final String CHILD_FIRST = 'Mayaqz';
    private static final String PARENT_EMAIL = 'janeqz.testfamily@example.com';
    private static final String PARENT_PHONE = '6045550199';
    private static final String CONTACT_CARE_CARD = '1234567891';
    private static final String MINOR_CARE_CARD = '9876543219';

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
        Test.setMock(HttpCalloutMock.class, new AnyCalloutMock());

        Account acc = new Account(Name = FAMILY_LAST + ' Household', Phone = PARENT_PHONE);
        insert acc;

        Contact parent = new Contact(
            AccountId = acc.Id,
            FirstName = PARENT_FIRST,
            LastName = FAMILY_LAST,
            Email = PARENT_EMAIL,
            Phone = PARENT_PHONE,
            Birthdate = Date.newInstance(1988, 3, 14),
            Child_s_Care_Care__c = CONTACT_CARE_CARD,
            Details_About_Allergies__c = 'Severe peanut allergy'
        );
        insert parent;

        insert new Minor__c(
            Account__c = acc.Id,
            First_Name__c = CHILD_FIRST,
            Last_Name__c = FAMILY_LAST,
            Date_of_Birth__c = Date.newInstance(2019, 10, 20),
            BC_Care_Card__c = MINOR_CARE_CARD
        );

                Opportunity party = new Opportunity(
            AccountId = acc.Id,
            Name = CHILD_FIRST + ' birthday',
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-330),
            Event_Date_and_Start_Time__c = Datetime.now().addDays(-330),
            Special_Guest_s_Name__c = CHILD_FIRST,
            Booking_Type__c = 'Party',
            Event_Type__c = 'Birthday',
            Activity_Room__c = 'Field',
            Party_Package__c = 'General',
            Pizza_or_Add_on_Preferences__c = CHILD_FIRST + ' is allergic to peanuts. Extra cheese pizza please.'
        );
        insert party;

        insert new Team_notes__c(
            Contact__c = parent.Id,
            Comments__c = '<p>' + PARENT_FIRST + ' called from 604-555-0199 about laser tag.</p><p>' + CHILD_FIRST +
                ' uses an asthma inhaler.</p><p>Email ' + PARENT_EMAIL + ' for the invoice.</p>'
        );
    }

    private static Account household() {
        return [SELECT Id FROM Account WHERE Name = :FAMILY_LAST + ' Household' LIMIT 1];
    }

    @IsTest
    static void contextContainsNoPersonalOrHealthData() {
        Test.startTest();
        FamilyContextBuilder.Result r = FamilyContextBuilder.build(household().Id);
        Test.stopTest();

        String json = r.contextJson.toLowerCase();
        List<String> forbidden = new List<String>{
            PARENT_FIRST, FAMILY_LAST, CHILD_FIRST, PARENT_EMAIL, PARENT_PHONE, '604-555-0199',
            CONTACT_CARE_CARD, MINOR_CARE_CARD, 'peanut', 'asthma', 'inhaler', '1988-03-14', '2019-10-20'
        };
        for (String f : forbidden) {
            System.assert(!json.contains(f.toLowerCase()), 'Context leaked forbidden value: ' + f);
        }
        System.assert(r.contextJson.contains('Person A'), 'Contacts should be tokenized');
        System.assert(r.contextJson.contains('Booking 1'), 'Bookings should be tokenized');
        System.assert(r.contextJson.contains(Redactor.HEALTH_MASK), 'Health sentences should be masked, not dropped silently');
        System.assert(r.contextJson.contains('laser tag'), 'Non-sensitive note text should survive redaction');
        System.assert(r.tokenToRecordId.containsKey('Person A'), 'Token map must resolve back to the Contact');
    }

    @IsTest
    static void fieldsSentNeverIncludesDenylistedFields() {
        FamilyContextBuilder.Result r = FamilyContextBuilder.build(household().Id);
        String sent = String.join(r.fieldsSent, ',');
        for (String denied : new List<String>{
            'Minor__c', 'Birthdate', 'Care_Card', 'Care_Care', 'Special_Guest', 'Medical', 'Details_About', 'Email', 'Phone'
        }) {
            System.assert(!sent.containsIgnoreCase(denied), 'Denylisted field declared as sent: ' + denied);
        }
    }

    @IsTest
    static void mockProducesSchemaAndRebookingTask() {
        FamilyContextBuilder.Result r = FamilyContextBuilder.build(household().Id);
        LlmClient client = LlmClientFactory.get();
        String raw = client.complete(FamilyInsightPrompt.SYSTEM_PROMPT, r.contextJson);

        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(raw);
        System.assert(out.containsKey('summary'));
        System.assert(out.containsKey('insights'));
        List<Object> tasks = (List<Object>) out.get('suggestedTasks');
        System.assertEquals(1, tasks.size(), 'Party ~330 days ago with nothing booked should give one rebooking task');
        Map<String, Object> t = (Map<String, Object>) tasks[0];
        System.assertEquals('Booking 1', t.get('relatedToken'));
        System.assert(r.tokenToRecordId.containsKey((String) t.get('relatedToken')), 'Task token must map to a real record');
        System.assertEquals('mock-rules-v1', client.modelName());
    }

    @IsTest
    static void emptyHouseholdSaysHistoryIsThin() {
        Account a = new Account(Name = 'Emptyqz Household');
        insert a;
        String raw = new MockLlmClient().complete('', FamilyContextBuilder.build(a.Id).contextJson);
        System.assert(raw.contains('History is thin'));
    }
}
