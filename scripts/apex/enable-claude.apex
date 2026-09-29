CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
s.LLM_Provider__c = 'claude';
s.LLM_Model__c = 'claude-sonnet-5';
s.Max_Output_Tokens__c = 4096;
upsert s;
System.debug('SET>> provider=' + s.LLM_Provider__c + ' model=' + s.LLM_Model__c);
