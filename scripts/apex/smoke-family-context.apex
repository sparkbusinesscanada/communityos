Account a = [SELECT Id FROM Account WHERE of_Parties_Hosted__c > 1 ORDER BY LastModifiedDate DESC LIMIT 1];
FamilyContextBuilder.Result r = FamilyContextBuilder.build(a.Id);
System.debug('CTX>>' + r.contextJson);
System.debug('OUT>>' + LlmClientFactory.get().complete(FamilyInsightPrompt.SYSTEM_PROMPT, r.contextJson));
