CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
s.Input_Cost_Per_MTok__c = 2;
s.Output_Cost_Per_MTok__c = 10;
if (s.Daily_AI_Call_Limit__c == null) { s.Daily_AI_Call_Limit__c = 200; }
upsert s;
