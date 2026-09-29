/**
 * Single switch point for the LLM provider.
 * Today it always returns the mock; when the API key is purchased,
 * this is the only class that changes.
 */
public with sharing class LlmClientFactory {
    @TestVisible
    private static LlmClient overrideClient;

    public static LlmClient get() {
        if (overrideClient != null) {
            return overrideClient;
        }
        return new MockLlmClient();
    }
}
