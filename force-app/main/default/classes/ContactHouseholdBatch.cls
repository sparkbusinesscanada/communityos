/**
 * One-off backfill: gives every Contact with a phone and no Account a household.
 * Run: Database.executeBatch(new ContactHouseholdBatch(), 200);
 */
public without sharing class ContactHouseholdBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Integer linked = 0;

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, Phone, MobilePhone, AccountId FROM Contact
            WHERE AccountId = null AND (Phone != null OR MobilePhone != null)
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<Contact> scope) {
        linked += ContactHouseholdService.link(scope, null);
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug(LoggingLevel.INFO, 'ContactHouseholdBatch linked ' + linked + ' contacts');
    }
}
