@IsTest
private class ContactHouseholdServiceTest {
    // Contacts without Email so the existing Square sync trigger never calls out.

    @IsTest
    static void newContactGetsHouseholdNamedWithPhone() {
        Contact a = new Contact(LastName = 'Hhtest', Phone = '(604) 555-0101');
        insert a;
        Contact b = new Contact(LastName = 'Hhtest2', Phone = '6045550101');
        insert b;
        Map<Id, Contact> got = new Map<Id, Contact>([SELECT Id, AccountId, Account.Name FROM Contact WHERE Id IN :new List<Id>{ a.Id, b.Id }]);
        System.assertEquals('6045550101', got.get(a.Id).Account.Name);
        System.assertEquals(got.get(a.Id).AccountId, got.get(b.Id).AccountId, 'Same phone, same household');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = '6045550101']);
    }

    @IsTest
    static void existingHouseholdIsReused() {
        Account h = new Account(Name = '7785550102', Phone = '7785550102');
        insert h;
        Contact c = new Contact(LastName = 'Hhtest', Phone = '+1 778 555 0102');
        insert c;
        System.assertEquals(h.Id, [SELECT AccountId FROM Contact WHERE Id = :c.Id].AccountId);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = '7785550102']);
    }

    @IsTest
    static void phoneChangeMovesAutoHouseholdButNotNamedAccount() {
        Contact auto = new Contact(LastName = 'Hhauto', Phone = '6045550103');
        insert auto;
        Account daycare = new Account(Name = 'Shining Star Daycare Test');
        insert daycare;
        Contact staff = new Contact(LastName = 'Hhdaycare', Phone = '6045550104', AccountId = daycare.Id);
        insert staff;

        Test.startTest();
        update new List<Contact>{
            new Contact(Id = auto.Id, Phone = '6045550199'),
            new Contact(Id = staff.Id, Phone = '6045550198')
        };
        Test.stopTest();

        System.assertEquals('6045550199', [SELECT Account.Name FROM Contact WHERE Id = :auto.Id].Account.Name, 'Moved to the new phone household');
        System.assertEquals(daycare.Id, [SELECT AccountId FROM Contact WHERE Id = :staff.Id].AccountId, 'Named accounts are never changed');
    }

    @IsTest
    static void noPhoneNoHousehold() {
        Contact c = new Contact(LastName = 'Hhnophone', Phone = '12345');
        insert c;
        System.assertEquals(null, [SELECT AccountId FROM Contact WHERE Id = :c.Id].AccountId);
    }

    @IsTest
    static void backfillBatchLinksOrphans() {
        ContactHouseholdService.running = true;
        insert new List<Contact>{
            new Contact(LastName = 'Hhorphan1', Phone = '6045550105'),
            new Contact(LastName = 'Hhorphan2', MobilePhone = '604.555.0106')
        };
        ContactHouseholdService.running = false;
        System.assertEquals(2, [SELECT COUNT() FROM Contact WHERE LastName LIKE 'Hhorphan%' AND AccountId = null]);
        Test.startTest();
        ContactHouseholdBatch b = new ContactHouseholdBatch();
        Database.executeBatch(b, 200);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE LastName LIKE 'Hhorphan%' AND AccountId = null]);
    }

    @IsTest
    static void importLoadsWithoutSquareSyncAndCreatesHouseholds() {
        Contact existing = new Contact(LastName = 'Hhimport', Phone = '6045550107');
        insert existing;
        String rows = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'squareId' => 'SQTEST1', 'firstName' => 'Pat', 'lastName' => 'Newfam', 'email' => 'pat@example.com', 'phone' => '6045550108' },
            new Map<String, Object>{ 'contactId' => existing.Id, 'squareId' => 'SQTEST2', 'lastName' => 'Hhimport' }
        });
        Test.startTest();
        Map<String, Integer> res = CustomerImport.load(rows);
        Test.stopTest();
        System.assertEquals(1, res.get('inserted'));
        System.assertEquals(1, res.get('updated'));
        System.assertEquals(0, res.get('failed'));
        Contact pat = [SELECT Square_Id__c, Account.Name FROM Contact WHERE Square_Id__c = 'SQTEST1'];
        System.assertEquals('6045550108', pat.Account.Name);
        System.assertEquals('SQTEST2', [SELECT Square_Id__c FROM Contact WHERE Id = :existing.Id].Square_Id__c);
        System.assertEquals(false, SquareIntegrationService.isProcessingSquareSync, 'Sync flag restored');
    }
}
