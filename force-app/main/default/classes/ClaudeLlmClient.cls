/**
 * Calls the Anthropic Messages API through the Anthropic_API named credential.
 * The API key never appears in code or metadata: it lives in the Anthropic external credential
 * (Setup > Named Credentials > External Credentials > Anthropic > Principals > ApiKey).
 */
public with sharing class ClaudeLlmClient implements LlmClient {
    public static final String DEFAULT_MODEL = 'claude-sonnet-5';
    private static final String API_VERSION = '2023-06-01';

    private final String model;
    private final Integer maxTokens;

    public ClaudeLlmClient(String model, Integer maxTokens) {
        this.model = String.isBlank(model) ? DEFAULT_MODEL : model;
        this.maxTokens = maxTokens == null || maxTokens <= 0 ? 1024 : maxTokens;
    }

    public String modelName() {
        return model;
    }

    public String complete(String systemPrompt, String contextJson) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Anthropic_API/v1/messages');
        req.setMethod('POST');
        req.setTimeout(60000);
        req.setHeader('content-type', 'application/json');
        req.setHeader('anthropic-version', API_VERSION);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'model' => model,
            'max_tokens' => maxTokens,
            'system' => systemPrompt,
            'messages' => new List<Object>{
                new Map<String, Object>{
                    'role' => 'user',
                    'content' => 'Household JSON:\n' + contextJson
                }
            }
        }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new LlmException('Claude API returned ' + res.getStatusCode() + ': ' + res.getBody().left(500));
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<String> parts = new List<String>();
        for (Object block : (List<Object>) body.get('content')) {
            Map<String, Object> b = (Map<String, Object>) block;
            if (b.get('type') == 'text') {
                parts.add((String) b.get('text'));
            }
        }
        if (parts.isEmpty()) {
            throw new LlmException('Claude API returned no text content');
        }
        return String.join(parts, '');
    }

    public class LlmException extends Exception {}
}
