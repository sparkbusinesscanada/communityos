/**
 * Nightly auto-task job: 45 days before the anniversary of a past party, create a follow-up task for staff
 * if the household has nothing booked ahead and no recent reminder.
 *
 * Deliberately rules-only (no LLM): the schedule must be exact, cheap and repeatable.
 * The AI is used on demand in Family 360, where judgement over free text adds value.
 *
 * Schedule: System.schedule('CommunityOS rebooking reminders', '0 0 6 * * ?', new RebookingReminderJob());
 */
public with sharing class RebookingReminderJob implements Database.Batchable<SObject>, Schedulable {
    public static final Integer LEAD_DAYS = 45;
    public static final String SUBJECT_PREFIX = 'Rebooking reminder';

    @TestVisible
    private Date today;

    public RebookingReminderJob() {
        this(Date.today());
    }

    @TestVisible
    private RebookingReminderJob(Date today) {
        this.today = today;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new RebookingReminderJob(), 100);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date anniversary = today.addDays(LEAD_DAYS);
        Integer m = anniversary.month();
        Integer d = anniversary.day();
        Datetime cutoff = Datetime.newInstance(today.addDays(-300), Time.newInstance(0, 0, 0, 0));
        return Database.getQueryLocator([
            SELECT Id, AccountId, OwnerId, Name, Party_Package__c, Event_Date_and_Start_Time__c, Billing_Contact__c
            FROM Opportunity
            WHERE IsWon = true
              AND Booking_Type__c = 'Party'
              AND AccountId != null
              AND Event_Date_and_Start_Time__c < :cutoff
              AND CALENDAR_MONTH(Event_Date_and_Start_Time__c) = :m
              AND DAY_IN_MONTH(Event_Date_and_Start_Time__c) = :d
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Opportunity> parties) {
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity o : parties) { accountIds.add(o.AccountId); }

        Set<Id> hasFutureBooking = new Set<Id>();
        Datetime nowTs = Datetime.now();
        for (Opportunity f : [
            SELECT AccountId FROM Opportunity
            WHERE AccountId IN :accountIds AND (IsClosed = false OR Event_Date_and_Start_Time__c >= :nowTs)
        ]) {
            hasFutureBooking.add(f.AccountId);
        }

        Set<Id> recentlyReminded = new Set<Id>();
        Datetime recent = Datetime.now().addDays(-90);
        for (Task t : [
            SELECT AccountId FROM Task
            WHERE AccountId IN :accountIds AND Subject LIKE :(SUBJECT_PREFIX + '%') AND CreatedDate >= :recent
        ]) {
            recentlyReminded.add(t.AccountId);
        }

        Map<Id, Contact> firstContact = new Map<Id, Contact>();
        for (Contact c : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds ORDER BY CreatedDate]) {
            if (!firstContact.containsKey(c.AccountId)) { firstContact.put(c.AccountId, c); }
        }

        List<Task> tasks = new List<Task>();
        Set<Id> done = new Set<Id>();
        for (Opportunity o : parties) {
            if (hasFutureBooking.contains(o.AccountId) || recentlyReminded.contains(o.AccountId) || done.contains(o.AccountId)) {
                continue;
            }
            done.add(o.AccountId);
            Date partyDate = o.Event_Date_and_Start_Time__c.date();
            Date anniversary = today.addDays(LEAD_DAYS);
            Id who = o.Billing_Contact__c != null ? o.Billing_Contact__c : firstContact.get(o.AccountId)?.Id;
            tasks.add(new Task(
                Subject = SUBJECT_PREFIX + ': offer this year\'s party',
                WhatId = o.Id,
                WhoId = who,
                OwnerId = o.OwnerId,
                ActivityDate = today.addDays(3),
                Status = 'Not Started',
                Priority = 'Normal',
                AI_Generated__c = false,
                AI_Reason__c = ('Party on ' + String.valueOf(partyDate) +
                    (o.Party_Package__c == null ? '' : ' (' + o.Party_Package__c + ')') +
                    '; anniversary ' + String.valueOf(anniversary) + '; nothing booked ahead.').left(255)
            ));
        }
        if (!tasks.isEmpty()) {
            Database.insert(tasks, false, AccessLevel.SYSTEM_MODE);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('RebookingReminderJob finished for anniversary date ' + today.addDays(LEAD_DAYS));
    }
}
