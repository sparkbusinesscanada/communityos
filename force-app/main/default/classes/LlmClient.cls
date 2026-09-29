/**
 * Contract for any large-language-model provider used by CommunityOS.
 * Implementations: MockLlmClient (deterministic, no network) and, later, a Claude client.
 */
public interface LlmClient {
    /**
     * @param systemPrompt fixed instructions and output schema
     * @param contextJson  pseudonymized, allowlisted family context
     * @return raw JSON string matching the FamilyInsight schema
     */
    String complete(String systemPrompt, String contextJson);

    /** Short identifier stored in logs, e.g. "mock" or "claude-sonnet-5". */
    String modelName();
}
