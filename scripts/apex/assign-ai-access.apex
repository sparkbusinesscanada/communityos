Id ps = [SELECT Id FROM PermissionSet WHERE Name = 'CommunityOS_AI_Access' LIMIT 1].Id;
Set<Id> have = new Set<Id>();
for (PermissionSetAssignment a : [SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId = :ps]) { have.add(a.AssigneeId); }
List<PermissionSetAssignment> add = new List<PermissionSetAssignment>();
for (User u : [SELECT Id FROM User WHERE IsActive = true AND Profile.Name IN ('Fun Circle Sales', 'System Administrator')]) {
    if (!have.contains(u.Id)) { add.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps)); }
}
insert add;
System.debug('ASSIGNED ' + add.size());
