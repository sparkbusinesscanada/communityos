for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'CommunityOS Square visit sync']) {
    System.abortJob(ct.Id);
}
System.schedule('CommunityOS Square visit sync', '0 30 2 * * ?', new SquareVisitSyncJob());
System.enqueueJob(new SquareVisitSync(2));
