/**
 * Calls the Anthropic Messages API through the Anthropic_API named credential.
 * The API key never appears in code or metadata: it lives in the Anthropic external credential
 * (Setup > Named Credentials > External Credentials > Anthropic > Principals > ApiKey).
 *
 * - Structured outputs: when a schema is given, output_config.format = json_schema makes the
 *   reply match it during generation (supported on Sonnet 5).
 * - Retries once on 429 / 500 / 504 / 529 (rate limit, server error, timeout, overloaded).
 * - Records usage (input/output tokens, retries) for cost logging.
 */
public with sharing class ClaudeLlmClient implements LlmClient {
    public static final String DEFAULT_MODEL = 'claude-sonnet-5';
    private static final String API_VERSION = '2023-06-01';
    @TestVisible static final Set<Integer> RETRYABLE = new Set<Integer>{ 429, 500, 504, 529 };
    @TestVisible static final Integer MAX_RETRIES = 1;

    private final String model;
    private final Integer maxTokens;
    private Map<String, Integer> usage = new Map<String, Integer>{ 'inputTokens' => 0, 'outputTokens' => 0, 'retries' => 0, 'schemaEnforced' => 0 };

    public ClaudeLlmClient(String model, Integer maxTokens) {
        this.model = String.isBlank(model) ? DEFAULT_MODEL : model;
        this.maxTokens = maxTokens == null || maxTokens <= 0 ? 4096 : maxTokens;
    }

    public String modelName() {
        return model;
    }

    public Map<String, Integer> lastUsage() {
        return usage;
    }

    public String complete(String systemPrompt, String contextJson) {
        return complete(systemPrompt, contextJson, null);
    }

    public String complete(String systemPrompt, String contextJson, Map<String, Object> outputSchema) {
        usage = new Map<String, Integer>{ 'inputTokens' => 0, 'outputTokens' => 0, 'retries' => 0,
            'schemaEnforced' => outputSchema == null ? 0 : 1 };
        Map<String, Object> payload = new Map<String, Object>{
            'model' => model,
            'max_tokens' => maxTokens,
            'system' => systemPrompt,
            'messages' => new List<Object>{
                new Map<String, Object>{ 'role' => 'user', 'content' => 'Household JSON:\n' + contextJson }
            }
        };
        if (outputSchema != null) {
            payload.put('output_config', new Map<String, Object>{
                'format' => new Map<String, Object>{ 'type' => 'json_schema', 'schema' => outputSchema }
            });
        }
        String requestBody = JSON.serialize(payload);

        HttpResponse res;
        for (Integer attempt = 0; attempt <= MAX_RETRIES; attempt++) {
            res = new Http().send(buildRequest(requestBody));
            if (!RETRYABLE.contains(res.getStatusCode()) || attempt == MAX_RETRIES) {
                break;
            }
            usage.put('retries', attempt + 1);
        }
        if (res.getStatusCode() != 200) {
            String busyNote = RETRYABLE.contains(res.getStatusCode())
                ? 'Claude is busy right now; try again in a minute. '
                : '';
            throw new LlmException(busyNote + 'Claude API returned ' + res.getStatusCode() + ': ' + res.getBody().left(500));
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> u = (Map<String, Object>) body.get('usage');
        if (u != null) {
            usage.put('inputTokens', toInt(u.get('input_tokens')));
            usage.put('outputTokens', toInt(u.get('output_tokens')));
        }
        if (body.get('stop_reason') == 'max_tokens') {
            throw new LlmException('Claude hit the output limit (' + maxTokens + ' tokens) before finishing; raise Max Output Tokens in CommunityOS Settings');
        }
        if (body.get('stop_reason') == 'refusal') {
            throw new LlmException('Claude declined to answer this request');
        }
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

    private static HttpRequest buildRequest(String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Anthropic_API/v1/messages');
        req.setMethod('POST');
        req.setTimeout(60000);
        req.setHeader('content-type', 'application/json');
        req.setHeader('anthropic-version', API_VERSION);
        req.setBody(body);
        return req;
    }

    private static Integer toInt(Object o) {
        return o == null ? 0 : Integer.valueOf(String.valueOf(o));
    }

    public class LlmException extends Exception {}
}
