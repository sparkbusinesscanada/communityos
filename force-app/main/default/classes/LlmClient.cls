/**
 * Contract for any large-language-model provider used by CommunityOS.
 * Implementations: MockLlmClient (rules, no network) and ClaudeLlmClient (Anthropic Messages API).
 */
public interface LlmClient {
    /**
     * @param systemPrompt fixed instructions
     * @param contextJson  pseudonymized, allowlisted family context
     * @return raw JSON string
     */
    String complete(String systemPrompt, String contextJson);

    /**
     * Same as complete, but the reply must match outputSchema (JSON Schema).
     * Providers that support structured outputs enforce it while generating; others ignore it
     * and the caller's validation still applies.
     */
    String complete(String systemPrompt, String contextJson, Map<String, Object> outputSchema);

    /** Usage of the last call: keys inputTokens, outputTokens, retries, schemaEnforced (0/1). */
    Map<String, Integer> lastUsage();

    /** Short identifier stored in logs, e.g. "mock-rules-v1" or "claude-sonnet-5". */
    String modelName();
}
