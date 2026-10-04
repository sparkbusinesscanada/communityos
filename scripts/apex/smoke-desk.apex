Id target = [SELECT Id FROM Account WHERE of_Parties_Hosted__c > 1 ORDER BY LastModifiedDate DESC LIMIT 1].Id;
DeskAgentService.DeskResult r = DeskAgentService.ask(target, new List<String>{ 'Last_Party', 'Upcoming_Booking', 'Balance_Due', 'Add_Ons', 'Last_Promise', 'Camps' });
System.debug('DESK>> ok=' + r.ok + ' model=' + r.model + ' error=' + r.error);
for (DeskAgentService.Answer a : r.answers) { System.debug('DESK>> ' + a.key + ' [' + a.status + '] ' + a.answer + ' | sources=' + a.sources); }
for (Desk_Question__c dq : [SELECT Question_Key__c, Booking__c, Order__c, Contact__c FROM Desk_Question__c WHERE AI_Call_Log__c = :r.logId]) { System.debug('DESK>> saved ' + dq.Question_Key__c + ' booking=' + (dq.Booking__c != null) + ' order=' + (dq.Order__c != null) + ' contact=' + (dq.Contact__c != null)); }
