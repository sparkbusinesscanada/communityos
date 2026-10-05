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
    static void reportsTruncatedAnswers() {
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(200, '{"stop_reason":"max_tokens","content":[{"type":"text","text":"{\\"summary\\":\\"cut"}]}'));
        try {
            new ClaudeLlmClient(null, 100).complete('sys', '{}');
            System.assert(false, 'Expected exception');
        } catch (ClaudeLlmClient.LlmException e) {
            System.assert(e.getMessage().contains('output limit'));
        }
    }

    private class SequenceMock implements HttpCalloutMock {
        List<Integer> statuses;
        Integer calls = 0;
        HttpRequest last;
        SequenceMock(List<Integer> statuses) { this.statuses = statuses; }
        public HttpResponse respond(HttpRequest req) {
            last = req;
            Integer st = statuses[Math.min(calls, statuses.size() - 1)];
            calls++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(st);
            res.setBody(st == 200
                ? '{"stop_reason":"end_turn","usage":{"input_tokens":1800,"output_tokens":420},"content":[{"type":"text","text":"{\\"answers\\":[]}"}]}'
                : '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}');
            return res;
        }
    }

    @IsTest
    static void sendsSchemaAndRecordsUsage() {
        SequenceMock m = new SequenceMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, m);
        ClaudeLlmClient c = new ClaudeLlmClient(null, null);
        String out = c.complete('sys', '{}', DeskAnswerPrompt.schemaFor(new List<String>{ 'Last_Party' }));
        System.assertEquals('{"answers":[]}', out);
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(m.last.getBody());
        Map<String, Object> fmt = (Map<String, Object>) ((Map<String, Object>) sent.get('output_config')).get('format');
        System.assertEquals('json_schema', fmt.get('type'));
        System.assertNotEquals(null, fmt.get('schema'));
        System.assertEquals(1800, c.lastUsage().get('inputTokens'));
        System.assertEquals(420, c.lastUsage().get('outputTokens'));
        System.assertEquals(1, c.lastUsage().get('schemaEnforced'));
        System.assertEquals(0, c.lastUsage().get('retries'));
    }

    @IsTest
    static void retriesOnceWhenBusy() {
        SequenceMock m = new SequenceMock(new List<Integer>{ 529, 200 });
        Test.setMock(HttpCalloutMock.class, m);
        ClaudeLlmClient c = new ClaudeLlmClient(null, null);
        c.complete('sys', '{}');
        System.assertEquals(2, m.calls);
        System.assertEquals(1, c.lastUsage().get('retries'));
        System.assertEquals(null, ((Map<String, Object>) JSON.deserializeUntyped(m.last.getBody())).get('output_config'), 'No schema when none given');
    }

    @IsTest
    static void busyTwiceGivesPlainMessage() {
        SequenceMock m = new SequenceMock(new List<Integer>{ 429, 429, 429 });
        Test.setMock(HttpCalloutMock.class, m);
        try {
            new ClaudeLlmClient(null, null).complete('sys', '{}');
            System.assert(false, 'Expected exception');
        } catch (ClaudeLlmClient.LlmException e) {
            System.assert(e.getMessage().startsWith('Claude is busy right now'), e.getMessage());
        }
        System.assertEquals(2, m.calls, 'One retry only');
    }

    @IsTest
    static void doesNotRetryAuthErrors() {
        SequenceMock m = new SequenceMock(new List<Integer>{ 401, 200 });
        Test.setMock(HttpCalloutMock.class, m);
        try {
            new ClaudeLlmClient(null, null).complete('sys', '{}');
            System.assert(false, 'Expected exception');
        } catch (ClaudeLlmClient.LlmException e) {
            System.assert(e.getMessage().contains('401'));
        }
        System.assertEquals(1, m.calls);
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
