/**
 * Single switch point for the LLM provider, driven by the CommunityOS Settings custom setting.
 *   LLM_Provider__c = 'claude' -> ClaudeLlmClient (needs the Anthropic API key in the external credential)
 *   anything else / blank      -> MockLlmClient (no network, no cost)
 */
public with sharing class LlmClientFactory {
    @TestVisible
    private static LlmClient overrideClient;

    public static LlmClient get() {
        if (overrideClient != null) {
            return overrideClient;
        }
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getInstance();
        if (s != null && s.LLM_Provider__c != null && s.LLM_Provider__c.equalsIgnoreCase('claude')) {
            return new ClaudeLlmClient(s.LLM_Model__c, s.Max_Output_Tokens__c == null ? null : s.Max_Output_Tokens__c.intValue());
        }
        return new MockLlmClient();
    }
}
