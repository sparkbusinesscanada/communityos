CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
s.Monthly_AI_Budget_USD__c = 25;
upsert s;
