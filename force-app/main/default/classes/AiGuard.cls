/**
 * Cost and usage guardrails shared by every AI feature.
 * - Daily cap on real-model calls for the whole org (CommunityOS Settings, default 200).
 * - Monthly budget in USD (estimated from logged tokens); blank means no cap.
 * - Rules mode (mock) is never capped and costs nothing.
 * - Copies token usage, retries and an estimated USD cost onto the AI call log.
 * - usage() feeds the banner on Family 360 so staff see what is left.
 */
public with sharing class AiGuard {
    public static final Integer DEFAULT_DAILY_LIMIT = 200;

    public class Usage {
        @AuraEnabled public String model;
        @AuraEnabled public Boolean rulesMode = false;
        @AuraEnabled public Integer callsToday = 0;
        @AuraEnabled public Integer dailyLimit = DEFAULT_DAILY_LIMIT;
        @AuraEnabled public Integer callsLeftToday = DEFAULT_DAILY_LIMIT;
        @AuraEnabled public Integer tokensToday = 0;
        @AuraEnabled public Integer tokensMonth = 0;
        @AuraEnabled public Decimal costToday = 0;
        @AuraEnabled public Decimal costMonth = 0;
        @AuraEnabled public Decimal monthlyBudget;
        @AuraEnabled public Decimal budgetLeft;
        @AuraEnabled public Boolean paused = false;
        @AuraEnabled public String pausedReason;
    }

    public static Usage usage() {
        Usage u = new Usage();
        LlmClient client = LlmClientFactory.get();
        u.model = client.modelName();
        u.rulesMode = u.model.startsWith('mock');
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
        if (s != null && s.Daily_AI_Call_Limit__c != null) {
            u.dailyLimit = s.Daily_AI_Call_Limit__c.intValue();
        }
        u.monthlyBudget = s == null ? null : s.Monthly_AI_Budget_USD__c;
        for (AggregateResult ar : [
            SELECT COUNT(Id) n, SUM(Input_Tokens__c) i, SUM(Output_Tokens__c) o, SUM(Est_Cost_USD__c) c
            FROM AI_Call_Log__c WHERE CreatedDate = TODAY AND (NOT Model__c LIKE 'mock%') WITH SYSTEM_MODE
        ]) {
            u.callsToday = (Integer) ar.get('n');
            u.tokensToday = toInt(ar.get('i')) + toInt(ar.get('o'));
            u.costToday = toDec(ar.get('c'));
        }
        for (AggregateResult ar : [
            SELECT SUM(Input_Tokens__c) i, SUM(Output_Tokens__c) o, SUM(Est_Cost_USD__c) c
            FROM AI_Call_Log__c WHERE CreatedDate = THIS_MONTH AND (NOT Model__c LIKE 'mock%') WITH SYSTEM_MODE
        ]) {
            u.tokensMonth = toInt(ar.get('i')) + toInt(ar.get('o'));
            u.costMonth = toDec(ar.get('c'));
        }
        u.callsLeftToday = Math.max(0, u.dailyLimit - u.callsToday);
        if (u.monthlyBudget != null) {
            u.budgetLeft = Math.max(0, u.monthlyBudget - u.costMonth).setScale(2);
        }
        if (!u.rulesMode) {
            if (u.callsLeftToday == 0) {
                u.paused = true;
                u.pausedReason = 'Daily AI limit reached (' + u.dailyLimit + ' calls today). It resets at midnight; an admin can raise it in CommunityOS Settings.';
            } else if (u.monthlyBudget != null && u.costMonth >= u.monthlyBudget) {
                u.paused = true;
                u.pausedReason = 'Monthly AI budget reached ($' + u.monthlyBudget.setScale(2) + '). AI pauses until the 1st; an admin can raise it in CommunityOS Settings.';
            }
        }
        return u;
    }

    /** Returns a staff-facing message when a cap is reached, otherwise null. */
    public static String dailyLimitMessage(LlmClient client) {
        if (client == null || client.modelName().startsWith('mock')) {
            return null;
        }
        Usage u = usage();
        return u.paused ? u.pausedReason : null;
    }

    public static void applyUsage(AI_Call_Log__c log, LlmClient client) {
        applyUsage(log, client.lastUsage());
    }

    /** Adds two calls' usage together (used when an empty structured reply is retried). */
    public static Map<String, Integer> addUsage(Map<String, Integer> a, Map<String, Integer> b) {
        Map<String, Integer> out = new Map<String, Integer>();
        for (String k : new List<String>{ 'inputTokens', 'outputTokens', 'retries' }) {
            Integer x = a == null || a.get(k) == null ? 0 : a.get(k);
            Integer y = b == null || b.get(k) == null ? 0 : b.get(k);
            out.put(k, x + y);
        }
        out.put('retries', out.get('retries') + 1);
        out.put('schemaEnforced', 0);
        return out;
    }

    public static void applyUsage(AI_Call_Log__c log, Map<String, Integer> u) {
        if (u == null) {
            return;
        }
        Integer inTok = u.get('inputTokens') == null ? 0 : u.get('inputTokens');
        Integer outTok = u.get('outputTokens') == null ? 0 : u.get('outputTokens');
        log.Input_Tokens__c = inTok;
        log.Output_Tokens__c = outTok;
        log.Retries__c = u.get('retries');
        log.Schema_Enforced__c = u.get('schemaEnforced') == 1;
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
        if (s != null && s.Input_Cost_Per_MTok__c != null && s.Output_Cost_Per_MTok__c != null) {
            log.Est_Cost_USD__c = ((inTok * s.Input_Cost_Per_MTok__c) + (outTok * s.Output_Cost_Per_MTok__c)) / 1000000;
        }
    }

    private static Integer toInt(Object o) { return o == null ? 0 : Integer.valueOf(String.valueOf(o)); }
    private static Decimal toDec(Object o) { return o == null ? 0 : Decimal.valueOf(String.valueOf(o)); }
}
