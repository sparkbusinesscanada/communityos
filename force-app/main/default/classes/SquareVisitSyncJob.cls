/**
 * Nightly scheduler for the Square visit sync. Reads Square only.
 * Schedule: System.schedule('CommunityOS Square visit sync', '0 30 2 * * ?', new SquareVisitSyncJob());
 */
public with sharing class SquareVisitSyncJob implements Schedulable {
    public void execute(SchedulableContext ctx) {
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getOrgDefaults();
        Integer days = s == null || s.Square_Sync_Days__c == null ? 2 : s.Square_Sync_Days__c.intValue();
        System.enqueueJob(new SquareVisitSync(days));
    }
}
