Id target = [SELECT Id FROM Account WHERE of_Parties_Hosted__c > 1 ORDER BY LastModifiedDate DESC LIMIT 1].Id;
FamilyInsightService.InsightResult r = FamilyInsightService.run(target);
System.debug('AI>> ok=' + r.ok + ' model=' + r.model);
System.debug('AI>> error=' + r.error);
System.debug('AI>> summary=' + r.summary);
for (FamilyInsightService.Insight i : r.insights) { System.debug('AI>> insight=' + i.title + ' | ' + i.detail); }
for (FamilyInsightService.SuggestedTask t : r.suggestedTasks) { System.debug('AI>> task=' + t.subject + ' | due ' + t.dueInDays + 'd | ' + t.relatedToken + ' | ' + t.reason); }
System.debug('AI>> dropped=' + r.droppedReasons);
