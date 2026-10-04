@IsTest
public class SquareVisitSyncTest {
    private class SquareMock implements HttpCalloutMock {
        Integer status;
        SquareMock(Integer status) { this.status = status; }
        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().startsWith('callout:Square_Production/orders/search'), 'Only reads orders/search');
            System.assertEquals('POST', req.getMethod());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(status == 200 ? sampleBody() : '{"errors":[{"code":"UNAUTHORIZED"}]}');
            return res;
        }
    }

    @TestVisible
    static String order(String id, String customer, Integer cents, String items, String closedAt) {
        return '{"id":"' + id + '","location_id":"LOC1","state":"COMPLETED","closed_at":"' + closedAt + '",' +
            (customer == null ? '' : '"customer_id":"' + customer + '",') +
            '"ticket_name":"Pam Example","source":{"name":"Point of Sale"},' +
            '"total_money":{"amount":' + cents + ',"currency":"CAD"},"total_tax_money":{"amount":50,"currency":"CAD"},' +
            '"total_tip_money":{"amount":0,"currency":"CAD"},"total_discount_money":{"amount":0,"currency":"CAD"},' +
            '"tenders":[{"type":"CARD","card_details":{"card":{"last_4":"9197","card_brand":"VISA"}}}]' +
            (items == null ? '' : ',"line_items":[' + items + ']') + '}';
    }

    @TestVisible
    static String item(String name, String variation, String qty, Integer cents) {
        return '{"name":"' + name + '","variation_name":"' + variation + '","quantity":"' + qty +
            '","total_money":{"amount":' + cents + ',"currency":"CAD"}}';
    }

    @TestVisible
    static String sampleBody() {
        String now = Datetime.now().addHours(-3).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String earlier = Datetime.now().addDays(-10).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        return '{"orders":[' +
            order('ORD-PARTY', 'SQC1', 108896, item('Private Party', 'Weekend PP - 2 Hours', '1', 74864) + ',' + item('Pizza', 'Cheese Pizza', '2', 3498), now) + ',' +
            order('ORD-DROPIN', 'SQC1', 2257, item('Admission', 'Toddler', '2', 2000) + ',' + item('Gatorade', 'Red', '1', 257), earlier) + ',' +
            order('ORD-NOSALE', 'SQC1', 0, null, now) + ',' +
            order('ORD-ANON', null, 1195, item('CASH BACK $10', '', '1', 1195), now) + ',' +
            order('ORD-UNKNOWN', 'SQC-NOT-IN-SF', 900, item('Socks', 'Kids', '1', 900), now) +
            ']}';
    }

    @TestSetup
    static void setup() {
        insert new CommunityOS_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Square_Location_Id__c = 'LOC1');
        Account acc = new Account(Name = 'Visitsync Household');
        insert acc;
        insert new Contact(AccountId = acc.Id, LastName = 'Visitsync', Square_Id__c = 'SQC1');
    }

    @IsTest
    static void nightlyJobCopiesCustomerOrdersOnly() {
        Test.setMock(HttpCalloutMock.class, new SquareMock(200));
        Test.startTest();
        new SquareVisitSyncJob().execute(null);
        Test.stopTest();

        Map<String, Visit__c> byId = new Map<String, Visit__c>();
        for (Visit__c v : [SELECT Square_Order_Id__c, Contact__c, Household__c, Amount__c, Tax__c, Offering__c,
                Item_Summary__c, Item_Count__c, Channel__c, Source_System__c FROM Visit__c]) {
            byId.put(v.Square_Order_Id__c, v);
        }
        System.assertEquals(new Set<String>{ 'ORD-PARTY', 'ORD-DROPIN', 'ORD-UNKNOWN' }, byId.keySet(),
            'No-sale and anonymous orders are skipped');
        Visit__c party = byId.get('ORD-PARTY');
        Id accId = [SELECT Id FROM Account WHERE Name = 'Visitsync Household'].Id;
        System.assertEquals(accId, party.Household__c, 'Matched by Square customer id');
        System.assertEquals(1088.96, party.Amount__c);
        System.assertEquals(0.50, party.Tax__c);
        System.assertEquals('Party', party.Offering__c, 'Biggest line decides the offering');
        System.assertEquals(3, party.Item_Count__c);
        System.assertEquals('Point of Sale', party.Channel__c);
        System.assertEquals('Square', party.Source_System__c);
        System.assert(!party.Item_Summary__c.contains('Pam') && !party.Item_Summary__c.contains('9197'), 'No names or card digits copied');
        System.assertEquals('Drop-in', byId.get('ORD-DROPIN').Offering__c);
        System.assertEquals(null, byId.get('ORD-UNKNOWN').Household__c, 'Unknown customer stays unlinked');
        System.assert(CommunityOS_Settings__c.getOrgDefaults().Square_Sync_Status__c.startsWith('OK: 3'));
    }

    @IsTest
    static void rerunDoesNotDuplicate() {
        SquareVisitSync.ingest(sampleBody());
        SquareVisitSync.Result r = SquareVisitSync.ingest(sampleBody());
        System.assertEquals(5, r.received);
        System.assertEquals(2, r.skipped);
        System.assertEquals(2, r.matched);
        System.assertEquals(3, [SELECT COUNT() FROM Visit__c]);
    }

    @IsTest
    static void failureIsRecordedAndNothingWritten() {
        Test.setMock(HttpCalloutMock.class, new SquareMock(401));
        Test.startTest();
        System.enqueueJob(new SquareVisitSync(2));
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Visit__c]);
        System.assert(CommunityOS_Settings__c.getOrgDefaults().Square_Sync_Status__c.contains('401'));
    }

    @IsTest
    static void depositOnlyOrderIsNotAVisit() {
        String day = Datetime.now().addDays(-5).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        SquareVisitSync.ingest('{"orders":[' + order('ORD-DEP', 'SQC1', 5500, item('$55 Non-refundable Deposit', '', '1', 5500), day) + ']}');
        Visit__c v = [SELECT Offering__c, Counts_As_Visit__c FROM Visit__c WHERE Square_Order_Id__c = 'ORD-DEP'];
        System.assertEquals('Party', v.Offering__c);
        System.assertEquals(false, v.Counts_As_Visit__c);
    }

    @IsTest
    static void offeringRules() {
        System.assertEquals('Laser tag', SquareVisitSync.offeringFor('Laser Tag 2 Game'));
        System.assertEquals('Café', SquareVisitSync.offeringFor('Kids Pizza Slice'));
        System.assertEquals('Drop-in', SquareVisitSync.offeringFor('Unlimited Play Toddler'));
        System.assertEquals('Camp', SquareVisitSync.offeringFor('Summer Camp Week 1'));
        System.assertEquals('Retail', SquareVisitSync.offeringFor('Grip Socks Small'));
        System.assertEquals('Other', SquareVisitSync.offeringFor('CASH BACK $10'));
        System.assertEquals('Drop-in', SquareVisitSync.offeringFor('Adult (18+ Years) Regular'));
        System.assertEquals('Drop-in', SquareVisitSync.offeringFor('Toddler (1 to 3 Y)'));
        System.assertEquals('Party', SquareVisitSync.offeringFor('Balloon Art'));
        System.assertEquals('Party', SquareVisitSync.offeringFor('$55 Non-refundable Deposit'));
        System.assertEquals('Café', SquareVisitSync.offeringFor('Pringles Medium Original'));
    }
}
