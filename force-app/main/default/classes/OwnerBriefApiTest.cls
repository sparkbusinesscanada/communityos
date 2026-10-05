@IsTest
private class OwnerBriefApiTest {
    @IsTest
    static void briefReportsSyncProblemsAndSpend() {
        insert new CommunityOS_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Square_Sync_Status__c = 'Failed on page 1: Square returned 401. Nothing changed.', Monthly_AI_Budget_USD__c = 1);
        AI_Call_Log__c log = new AI_Call_Log__c(Model__c = 'claude-sonnet-5', Status__c = 'Success', Est_Cost_USD__c = 0.9);
        insert log;
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        OwnerBriefApi.Brief b = OwnerBriefApi.get();
        System.assertEquals(String.valueOf(Date.today()), b.forDate);
        System.assertEquals(0.90, b.aiCostThisMonth);
        System.assert(b.needsAttention);
        System.assertEquals(2, b.attention.size(), String.valueOf(b.attention));
        String json = JSON.serialize(b);
        System.assert(!json.contains('@') , 'No contact details in the brief');
    }
}
