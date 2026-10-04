/**
 * Answers the checklist questions staff tick in Family 360, in ONE LLM call, and records each
 * question + answer as a Desk_Question__c linked to the household and the booking / order / contact it cited.
 *
 * Guardrails (deterministic, after the model):
 *  - output must parse into one answer per question key
 *  - an "answered" answer must cite at least one record token that exists in the context; otherwise Blocked
 *  - any email or phone number in the output blocks the whole response
 */
public with sharing class DeskAgentService {
    public static final String STATUS_ANSWERED = 'Answered';
    public static final String STATUS_NOT_IN_RECORDS = 'Not in records';
    public static final String STATUS_BLOCKED = 'Blocked';

    public class Question {
        @AuraEnabled public String key;
        @AuraEnabled public String question;
        @AuraEnabled public String offering;
    }

    public class SourceLink {
        @AuraEnabled public String label;
        @AuraEnabled public Id recordId;
        public SourceLink(String label, Id recordId) {
            this.label = label;
            this.recordId = recordId;
        }
    }

    public class Answer {
        @AuraEnabled public List<SourceLink> sourceLinks = new List<SourceLink>();
        @AuraEnabled public String key;
        @AuraEnabled public String question;
        @AuraEnabled public String status;
        @AuraEnabled public String answer;
        @AuraEnabled public List<String> sources = new List<String>();
        @AuraEnabled public Id deskQuestionId;
        @AuraEnabled public Id relatedRecordId;
    }

    public class DeskResult {
        @AuraEnabled public Boolean ok = false;
        @AuraEnabled public String error;
        @AuraEnabled public String model;
        @AuraEnabled public Id logId;
        @AuraEnabled public List<Answer> answers = new List<Answer>();
    }

    public static List<Question> templates() {
        Map<Integer, List<Desk_Question_Template__mdt>> bySort = new Map<Integer, List<Desk_Question_Template__mdt>>();
        for (Desk_Question_Template__mdt t : Desk_Question_Template__mdt.getAll().values()) {
            if (!t.Active__c) { continue; }
            Integer sortKey = t.Sort_Order__c == null ? 9999 : t.Sort_Order__c.intValue();
            if (!bySort.containsKey(sortKey)) { bySort.put(sortKey, new List<Desk_Question_Template__mdt>()); }
            bySort.get(sortKey).add(t);
        }
        List<Integer> keys = new List<Integer>(bySort.keySet());
        keys.sort();
        List<Question> out = new List<Question>();
        for (Integer k : keys) {
            for (Desk_Question_Template__mdt t : bySort.get(k)) {
                Question q = new Question();
                q.key = t.DeveloperName;
                q.question = t.Question__c;
                q.offering = t.Offering__c;
                out.add(q);
            }
        }
        return out;
    }

    public static DeskResult ask(Id accountId, List<String> keys) {
        DeskResult res = new DeskResult();
        Map<String, Question> byKey = new Map<String, Question>();
        for (Question q : templates()) { byKey.put(q.key, q); }
        List<Question> asked = new List<Question>();
        for (String k : keys == null ? new List<String>() : keys) {
            if (byKey.containsKey(k)) { asked.add(byKey.get(k)); }
        }
        if (asked.isEmpty()) {
            res.error = 'Tick at least one question.';
            return res;
        }

        LlmClient client = LlmClientFactory.get();
        res.model = client.modelName();
        FamilyContextBuilder.Result ctx = FamilyContextBuilder.build(accountId);
        List<Object> qs = new List<Object>();
        for (Question q : asked) { qs.add(new Map<String, Object>{ 'key' => q.key, 'question' => q.question }); }
        String payload = JSON.serialize(new Map<String, Object>{
            'questions' => qs,
            'household' => JSON.deserializeUntyped(ctx.contextJson)
        });

        AI_Call_Log__c log = new AI_Call_Log__c(
            Account__c = accountId,
            Model__c = client.modelName(),
            Prompt_Version__c = DeskAnswerPrompt.VERSION,
            Context_Json__c = payload.left(131072),
            Fields_Sent__c = String.join(ctx.fieldsSent, '\n').left(32768)
        );
        Long started = System.currentTimeMillis();
        Map<String, Answer> parsed = new Map<String, Answer>();
        try {
            String raw = client.complete(DeskAnswerPrompt.SYSTEM_PROMPT, payload);
            log.Response_Json__c = raw == null ? null : raw.left(131072);
            parsed = parse(raw, ctx.tokenToRecordId);
            res.ok = true;
            log.Status__c = 'Success';
        } catch (Exception e) {
            res.error = 'The AI answer could not be used: ' + e.getMessage();
            log.Status__c = 'Error';
            log.Error__c = (e.getTypeName() + ': ' + e.getMessage()).left(32768);
        }
        log.Duration_ms__c = System.currentTimeMillis() - started;
        insert as system log;
        res.logId = log.Id;
        if (!res.ok) {
            return res;
        }

        Id primaryContact = null;
        for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :accountId WITH USER_MODE ORDER BY CreatedDate LIMIT 1]) {
            primaryContact = c.Id;
        }
        if (primaryContact == null) {
            Set<Id> billing = new Set<Id>();
            for (Opportunity o : [SELECT Billing_Contact__c FROM Opportunity WHERE AccountId = :accountId AND Billing_Contact__c != null
                                  WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 5]) {
                billing.add(o.Billing_Contact__c);
            }
            for (Contact c : [SELECT Id FROM Contact WHERE Id IN :billing WITH USER_MODE LIMIT 1]) {
                primaryContact = c.Id;
            }
        }

        List<Desk_Question__c> rows = new List<Desk_Question__c>();
        Integer blocked = 0;
        for (Question q : asked) {
            Answer a = parsed.containsKey(q.key) ? parsed.get(q.key) : missing(q.key);
            a.question = q.question;
            if (a.status == STATUS_BLOCKED) { blocked++; }
            Desk_Question__c dq = new Desk_Question__c(
                Account__c = accountId,
                Contact__c = primaryContact,
                Question__c = q.question,
                Question_Key__c = q.key,
                Offering__c = q.offering,
                Answer__c = a.answer,
                Answer_Status__c = a.status,
                Source_Records__c = String.join(a.sources, ', ').left(255),
                Answered_By_Agent__c = a.status == STATUS_ANSWERED,
                Asked_At__c = Datetime.now(),
                AI_Call_Log__c = log.Id
            );
            for (String token : a.sources) {
                Id rid = ctx.tokenToRecordId.get(token);
                if (rid == null) { continue; }
                a.sourceLinks.add(new SourceLink(token, rid));
                String type = rid.getSObjectType().getDescribe().getName();
                if (type == 'Opportunity' && dq.Booking__c == null) { dq.Booking__c = rid; }
                if (type == 'Order' && dq.Order__c == null) { dq.Order__c = rid; }
                if (type == 'Contact') { dq.Contact__c = rid; }
                if (a.relatedRecordId == null && type != 'Account') { a.relatedRecordId = rid; }
            }
            rows.add(dq);
            res.answers.add(a);
        }
        insert as user rows;
        for (Integer i = 0; i < rows.size(); i++) {
            res.answers[i].deskQuestionId = rows[i].Id;
        }
        if (blocked > 0) {
            update as system new AI_Call_Log__c(Id = log.Id, Status__c = 'Filtered',
                Error__c = blocked + ' answer(s) blocked: answered without a valid source record');
        }
        return res;
    }

    public static void markOutcome(Id deskQuestionId, String outcome) {
        Desk_Question__c dq = new Desk_Question__c(Id = deskQuestionId);
        dq.Resolved_On_Spot__c = outcome == 'resolved';
        dq.Escalated_To_Owner__c = outcome == 'escalated';
        update as user dq;
    }

    @TestVisible
    private static Map<String, Answer> parse(String raw, Map<String, Id> tokenMap) {
        if (String.isBlank(raw)) {
            throw new DeskException('empty response');
        }
        Integer first = raw.indexOf('{');
        Integer last = raw.lastIndexOf('}');
        if (first < 0 || last <= first) {
            throw new DeskException('response is not JSON');
        }
        String body = raw.substring(first, last + 1);
        if (Pattern.compile('[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}').matcher(body).find()
            || Pattern.compile('(?<!\\d)\\(?\\d{3}\\)?[\\s.-]?\\d{3}[\\s.-]?\\d{4}(?!\\d)').matcher(body).find()) {
            throw new DeskException('response contained contact details and was blocked');
        }
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
        if (!(m.get('answers') instanceof List<Object>)) {
            throw new DeskException('missing answers');
        }
        Map<String, Answer> out = new Map<String, Answer>();
        for (Object o : (List<Object>) m.get('answers')) {
            Map<String, Object> am = (Map<String, Object>) o;
            Answer a = new Answer();
            a.key = String.valueOf(am.get('key'));
            a.answer = am.get('answer') == null ? '' : String.valueOf(am.get('answer')).left(1000);
            if (am.get('sources') instanceof List<Object>) {
                for (Object s : (List<Object>) am.get('sources')) {
                    String token = String.valueOf(s);
                    if (tokenMap.containsKey(token)) { a.sources.add(token); }
                }
            }
            String status = String.valueOf(am.get('status'));
            if (status == 'answered') {
                if (a.sources.isEmpty()) {
                    a.status = STATUS_BLOCKED;
                    a.answer = 'Blocked: the AI gave an answer without a source record. Check the household history directly.';
                } else {
                    a.status = STATUS_ANSWERED;
                }
            } else {
                a.status = STATUS_NOT_IN_RECORDS;
            }
            out.put(a.key, a);
        }
        return out;
    }

    private static Answer missing(String key) {
        Answer a = new Answer();
        a.key = key;
        a.status = STATUS_NOT_IN_RECORDS;
        a.answer = 'The AI did not return an answer for this question.';
        return a;
    }

    public class DeskException extends Exception {}
}
