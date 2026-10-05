/**
 * Orchestrates one AI insight call: build context -> call LLM -> validate output -> log.
 * Deterministic guardrails live here, not in the prompt:
 *  - output must parse as the agreed JSON schema
 *  - every suggested task must point at a token that exists in the context (no invented records)
 *  - at most 3 tasks, due in 0-30 days, text trimmed to field sizes
 *  - output is scanned for emails / phone numbers and rejected if any appear
 */
public with sharing class FamilyInsightService {
    public static final Integer MAX_TASKS = 3;

    public class Insight {
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
    }

    public class SuggestedTask {
        @AuraEnabled public String subject;
        @AuraEnabled public String reason;
        @AuraEnabled public Integer dueInDays;
        @AuraEnabled public String relatedToken;
        @AuraEnabled public Id relatedRecordId;
    }

    public class InsightResult {
        @AuraEnabled public Boolean ok = false;
        @AuraEnabled public String summary;
        @AuraEnabled public List<Insight> insights = new List<Insight>();
        @AuraEnabled public List<SuggestedTask> suggestedTasks = new List<SuggestedTask>();
        @AuraEnabled public List<String> droppedReasons = new List<String>();
        @AuraEnabled public String model;
        @AuraEnabled public Id logId;
        @AuraEnabled public String error;
    }

    public static InsightResult run(Id accountId) {
        return run(accountId, null);
    }

    /**
     * @param deferredLogs when not null, the log is added here instead of inserted, so callers can make
     *                     several AI callouts first and insert all logs at the end (no DML before callouts).
     */
    public static InsightResult run(Id accountId, List<AI_Call_Log__c> deferredLogs) {
        InsightResult res = new InsightResult();
        LlmClient client = LlmClientFactory.get();
        res.model = client.modelName();
        FamilyContextBuilder.Result ctx = FamilyContextBuilder.build(accountId);

        AI_Call_Log__c log = new AI_Call_Log__c(
            Account__c = accountId,
            Model__c = client.modelName(),
            Prompt_Version__c = FamilyInsightPrompt.VERSION,
            Context_Json__c = ctx.contextJson.left(131072),
            Fields_Sent__c = String.join(ctx.fieldsSent, '\n').left(32768)
        );

        Long started = System.currentTimeMillis();
        String raw;
        String limitMsg = AiGuard.dailyLimitMessage(client);
        Map<String, Integer> usage;
        Boolean retriedEmpty = false;
        try {
            if (limitMsg != null) {
                throw new InsightException(limitMsg);
            }
            raw = client.complete(FamilyInsightPrompt.SYSTEM_PROMPT, ctx.contextJson, FamilyInsightPrompt.OUTPUT_SCHEMA);
            usage = client.lastUsage();
            try {
                parseAndValidate(raw, ctx.tokenToRecordId, res);
            } catch (EmptyReplyException empty) {
                // A schema-valid but empty reply: retry once with prompt-only JSON. Same guardrails apply.
                raw = client.complete(FamilyInsightPrompt.SYSTEM_PROMPT, ctx.contextJson);
                usage = AiGuard.addUsage(usage, client.lastUsage());
                retriedEmpty = true;
                parseAndValidate(raw, ctx.tokenToRecordId, res);
            }
            log.Response_Json__c = raw == null ? null : raw.left(131072);
            res.ok = true;
            log.Status__c = res.droppedReasons.isEmpty() ? 'Success' : 'Filtered';
        } catch (Exception e) {
            res.ok = false;
            res.error = 'The AI response could not be used: ' + e.getMessage();
            log.Status__c = 'Error';
            log.Error__c = (e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString()).left(32768);
        }
        log.Duration_ms__c = System.currentTimeMillis() - started;
        if (limitMsg != null) {
            res.error = limitMsg;
            log.Status__c = 'Limit reached';
        } else {
            AiGuard.applyUsage(log, usage == null ? client.lastUsage() : usage);
        }
        log.Tasks_Suggested__c = res.suggestedTasks.size();
        if (!res.droppedReasons.isEmpty()) {
            log.Error__c = ('Dropped by guardrails:\n' + String.join(res.droppedReasons, '\n')).left(32768);
        }
        if (retriedEmpty) {
            log.Error__c = ('Empty structured reply; retried once without schema.\n' + (log.Error__c == null ? '' : log.Error__c)).left(32768);
        }
        if (deferredLogs != null) {
            deferredLogs.add(log);
            return res;
        }
        insert as system log;
        res.logId = log.Id;
        return res;
    }

    @TestVisible
    private static void parseAndValidate(String raw, Map<String, Id> tokenMap, InsightResult res) {
        if (String.isBlank(raw)) {
            throw new InsightException('empty response');
        }
        String trimmed = raw.trim();
        Integer first = trimmed.indexOf('{');
        Integer last = trimmed.lastIndexOf('}');
        if (first < 0 || last <= first) {
            throw new InsightException('response is not JSON');
        }
        trimmed = trimmed.substring(first, last + 1);

        if (Pattern.compile('[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}').matcher(trimmed).find()
            || Pattern.compile('(?<!\\d)\\(?\\d{3}\\)?[\\s.-]?\\d{3}[\\s.-]?\\d{4}(?!\\d)').matcher(trimmed).find()) {
            throw new InsightException('response contained contact details and was blocked');
        }

        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(trimmed);
        if (!(m.get('summary') instanceof String)) {
            throw new InsightException('missing summary');
        }
        if (String.isBlank((String) m.get('summary'))) {
            throw new EmptyReplyException('empty summary');
        }
        res.summary = ((String) m.get('summary')).left(1000);

        if (m.get('insights') instanceof List<Object>) {
            for (Object o : (List<Object>) m.get('insights')) {
                Map<String, Object> im = (Map<String, Object>) o;
                Insight i = new Insight();
                i.title = String.valueOf(im.get('title')).left(120);
                i.detail = String.valueOf(im.get('detail')).left(500);
                res.insights.add(i);
                if (res.insights.size() == 4) { break; }
            }
        }

        if (m.get('suggestedTasks') instanceof List<Object>) {
            for (Object o : (List<Object>) m.get('suggestedTasks')) {
                Map<String, Object> tm = (Map<String, Object>) o;
                String token = tm.get('relatedToken') == null ? 'Household' : String.valueOf(tm.get('relatedToken'));
                if (!tokenMap.containsKey(token)) {
                    res.droppedReasons.add('Task "' + tm.get('subject') + '" referenced unknown record ' + token);
                    continue;
                }
                if (res.suggestedTasks.size() == MAX_TASKS) {
                    res.droppedReasons.add('Task "' + tm.get('subject') + '" exceeded the ' + MAX_TASKS + '-task limit');
                    continue;
                }
                SuggestedTask t = new SuggestedTask();
                t.subject = String.valueOf(tm.get('subject')).left(255);
                t.reason = tm.get('reason') == null ? '' : String.valueOf(tm.get('reason')).left(255);
                Integer due = 2;
                try {
                    due = Integer.valueOf(tm.get('dueInDays'));
                } catch (Exception ignored) {
                    due = 2;
                }
                t.dueInDays = Math.max(0, Math.min(30, due == null ? 2 : due));
                t.relatedToken = token;
                t.relatedRecordId = tokenMap.get(token);
                res.suggestedTasks.add(t);
            }
        }
    }

    public class InsightException extends Exception {}

    public class EmptyReplyException extends Exception {}
}
