@IsTest
private class ClaudeLlmClientTest {
    private class ClaudeMock implements HttpCalloutMock {
        Integer status;
        String body;
        HttpRequest captured;
        ClaudeMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            captured = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    @IsTest
    static void sendsMessagesRequestAndReturnsText() {
        ClaudeMock m = new ClaudeMock(200,
            '{"content":[{"type":"text","text":"{\\"summary\\":\\"ok\\",\\"insights\\":[],\\"suggestedTasks\\":[]}"}]}');
        Test.setMock(HttpCalloutMock.class, m);
        String out = new ClaudeLlmClient(null, null).complete('sys', '{"today":"2026-09-29"}');
        System.assert(out.contains('"summary"'));
        System.assertEquals('callout:Anthropic_API/v1/messages', m.captured.getEndpoint());
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(m.captured.getBody());
        System.assertEquals(ClaudeLlmClient.DEFAULT_MODEL, sent.get('model'));
        System.assertEquals('sys', sent.get('system'));
        System.assertEquals(null, m.captured.getHeader('x-api-key'), 'Key must come from the named credential, not code');
    }

    @IsTest
    static void surfacesApiErrors() {
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(401, '{"error":{"message":"invalid x-api-key"}}'));
        try {
            new ClaudeLlmClient('claude-sonnet-5', 512).complete('sys', '{}');
            System.assert(false, 'Expected exception');
        } catch (ClaudeLlmClient.LlmException e) {
            System.assert(e.getMessage().contains('401'));
        }
    }

    @IsTest
    static void factoryHonoursSetting() {
        System.assert(LlmClientFactory.get() instanceof MockLlmClient, 'Default is mock');
        insert new CommunityOS_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), LLM_Provider__c = 'claude', LLM_Model__c = 'claude-sonnet-5');
        LlmClient c = LlmClientFactory.get();
        System.assert(c instanceof ClaudeLlmClient);
        System.assertEquals('claude-sonnet-5', c.modelName());
    }
}
