Id acc = [SELECT AccountId FROM Opportunity WHERE StageName = 'Closed Won' AND Booking_Type__c = 'Party' AND AccountId != null ORDER BY CloseDate DESC LIMIT 1].AccountId;
List<AI_Call_Log__c> logs = new List<AI_Call_Log__c>();
FamilyInsightService.InsightResult r = FamilyInsightService.run(acc, logs);
System.debug('INSIGHT ok=' + r.ok + ' err=' + r.error + ' tasks=' + r.suggestedTasks.size() + ' dropped=' + r.droppedReasons);
for (AI_Call_Log__c l : logs) {
    System.debug('LOG status=' + l.Status__c + ' model=' + l.Model__c + ' prompt=' + l.Prompt_Version__c + ' in=' + l.Input_Tokens__c + ' out=' + l.Output_Tokens__c + ' cost=' + l.Est_Cost_USD__c + ' schema=' + l.Schema_Enforced__c + ' retries=' + l.Retries__c + ' ms=' + l.Duration_ms__c);
}
insert logs;
