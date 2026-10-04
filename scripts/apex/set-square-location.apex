CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
s.Square_Location_Id__c = 'L7A9E1RN6DM8D';
s.Allow_Live_Writes__c = false;
upsert s;
System.debug('SET>> ok');
