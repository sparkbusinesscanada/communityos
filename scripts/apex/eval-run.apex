// CommunityOS eval: run the insight pipeline on a sample of real households and score it.
// Metrics: PII leak rate in context sent to AI, valid-output rate, task-grounding rate, avg latency.
Integer sampleSize = 3;
Integer offsetRows = 0;
List<Account> households_list = [
    SELECT Id FROM Account
    WHERE Id IN (SELECT AccountId FROM Opportunity WHERE Event_Date_and_Start_Time__c = LAST_N_DAYS:540)
    ORDER BY LastModifiedDate DESC LIMIT :sampleSize OFFSET :offsetRows
];

Integer households = 0, leaks = 0, okRuns = 0, tasks = 0, dropped = 0, withInsight = 0;
Long totalMs = 0;
List<String> leakDetails = new List<String>();
List<AI_Call_Log__c> logs = new List<AI_Call_Log__c>();

for (Account a : households_list) {
    households++;
    Set<String> secrets = new Set<String>();
    for (Contact c : [SELECT FirstName, LastName, Email, Phone, MobilePhone, Child_s_Care_Care__c FROM Contact WHERE AccountId = :a.Id]) {
        for (String v : new List<String>{ c.FirstName, c.LastName, c.Email, c.Child_s_Care_Care__c }) {
            if (v != null && v.trim().length() >= 4) { secrets.add(v.trim().toLowerCase()); }
        }
        for (String p : new List<String>{ c.Phone, c.MobilePhone }) {
            if (p != null) {
                String d = p.replaceAll('[^0-9]', '');
                if (d.length() >= 10) { secrets.add(d.right(10)); }
            }
        }
    }
    for (Minor__c m : [SELECT First_Name__c, Last_Name__c, BC_Care_Card__c FROM Minor__c WHERE Account__c = :a.Id]) {
        for (String v : new List<String>{ m.First_Name__c, m.Last_Name__c, m.BC_Care_Card__c }) {
            if (v != null && v.trim().length() >= 4) { secrets.add(v.trim().toLowerCase()); }
        }
    }

    FamilyContextBuilder.Result ctx = FamilyContextBuilder.build(a.Id);
    String haystack = ctx.contextJson.toLowerCase();
    String digitsOnly = ctx.contextJson.replaceAll('[^0-9]', ' ');
    for (String s : secrets) {
        Boolean hit = s.isNumeric() ? digitsOnly.contains(s) : Pattern.compile('\\b' + Pattern.quote(s) + '\\b').matcher(haystack).find();
        if (hit) {
            leaks++;
            leakDetails.add(a.Id + ' leaked a value of length ' + s.length());
        }
    }

    FamilyInsightService.InsightResult r = FamilyInsightService.run(a.Id, logs);
    if (r.ok) { okRuns++; }
    tasks += r.suggestedTasks.size();
    dropped += r.droppedReasons.size();
    if (!r.insights.isEmpty() || !r.suggestedTasks.isEmpty()) { withInsight++; }
    totalMs += logs[logs.size() - 1].Duration_ms__c.longValue();
}

insert logs;
System.debug('EVAL>> model=' + LlmClientFactory.get().modelName() + ' prompt=' + FamilyInsightPrompt.VERSION);
System.debug('EVAL>> households=' + households);
System.debug('EVAL>> pii_leaks=' + leaks + ' (target 0)');
System.debug('EVAL>> valid_output=' + okRuns + '/' + households);
System.debug('EVAL>> households_with_an_insight_or_task=' + withInsight + '/' + households);
System.debug('EVAL>> tasks_suggested=' + tasks + ' dropped_by_guardrails=' + dropped);
System.debug('EVAL>> avg_latency_ms=' + (households == 0 ? 0 : totalMs / households));
for (String d : leakDetails) { System.debug('EVAL>> LEAK ' + d); }
