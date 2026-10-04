/**
 * Builds the pseudonymized, allowlisted household context sent to the LLM.
 *
 * Guardrails (see docs/data-map.md):
 *  - Only fields listed in the SOQL below are ever read for the context. Minor__c and all child/medical
 *    Contact fields are never queried for output.
 *  - Names, emails and phones are replaced by tokens (Person A, Booking 1...). The token map stays in Salesforce.
 *  - Free text passes through Redactor, which also masks every known family name (adults and minors).
 */
public with sharing class FamilyContextBuilder {
    @TestVisible
    private static final Integer MAX_ROWS = 20;

    public class Result {
        public String contextJson;
        public Map<String, Id> tokenToRecordId = new Map<String, Id>();
        public List<String> fieldsSent = new List<String>();
    }

    public static Result build(Id accountId) {
        Result r = new Result();
        Map<String, Object> ctx = new Map<String, Object>();
        Date today = Date.today();
        ctx.put('today', String.valueOf(today));

        Account acc = [
            SELECT Id, CreatedDate, Number_of_Bookings__c, of_Parties_Hosted__c, Group_Type__c, Is_DayCare__c,
                   Visit_Frequency__c, Heard_About_Us__c, Interests__c, Preferred_Contact__c, Segment__c
            FROM Account WHERE Id = :accountId WITH USER_MODE
        ];
        r.tokenToRecordId.put('Household', acc.Id);
        ctx.put('household', new Map<String, Object>{
            'customerSince' => String.valueOf(acc.CreatedDate.date()),
            'bookingCount' => acc.Number_of_Bookings__c,
            'partiesHosted' => acc.of_Parties_Hosted__c,
            'groupType' => acc.Group_Type__c,
            'isDayCare' => acc.Is_DayCare__c,
            'visitFrequency' => acc.Visit_Frequency__c,
            'heardAboutUs' => acc.Heard_About_Us__c,
            'interests' => acc.Interests__c,
            'preferredContact' => acc.Preferred_Contact__c,
            'segment' => acc.Segment__c
        });
        r.fieldsSent.addAll(new List<String>{
            'Account.CreatedDate', 'Account.Number_of_Bookings__c', 'Account.of_Parties_Hosted__c',
            'Account.Group_Type__c', 'Account.Is_DayCare__c', 'Account.Visit_Frequency__c', 'Account.Heard_About_Us__c',
            'Account.Interests__c', 'Account.Preferred_Contact__c', 'Account.Segment__c'
        });

        Set<String> knownNames = collectKnownNames(accountId);

        List<Contact> contacts = [
            SELECT Id, Email, Phone, MobilePhone, Relationship__c, Unsubscribe__c, Square_Origin__c
            FROM Contact WHERE AccountId = :accountId WITH USER_MODE ORDER BY CreatedDate LIMIT :MAX_ROWS
        ];
        Set<Id> contactIds = new Set<Id>();
        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        List<Object> people = new List<Object>();
        Integer i = 0;
        for (Contact c : contacts) {
            String token = 'Person ' + letter(i++);
            r.tokenToRecordId.put(token, c.Id);
            contactIds.add(c.Id);
            if (String.isNotBlank(c.Email)) { emails.add(c.Email); }
            if (String.isNotBlank(c.Phone)) { phones.add(c.Phone); }
            if (String.isNotBlank(c.MobilePhone)) { phones.add(c.MobilePhone); }
            people.add(new Map<String, Object>{
                'token' => token,
                'relationship' => c.Relationship__c,
                'unsubscribed' => c.Unsubscribe__c,
                'cameFromSquare' => c.Square_Origin__c
            });
        }
        ctx.put('people', people);
        r.fieldsSent.addAll(new List<String>{ 'Contact.Relationship__c', 'Contact.Unsubscribe__c', 'Contact.Square_Origin__c' });

        List<Opportunity> bookings = [
            SELECT Id, StageName, Amount, Event_Type__c, Booking_Type__c, Party_Package__c, Activity_Room__c,
                   Event_Date_and_Start_Time__c, Estimated_Children__c, Estimated_Adults__c,
                   Summary_of_Add_Ons__c, Pizza_or_Add_on_Preferences__c, Laser_Tag__c,
                   Reason_for_Cancellation__c, Party_Re_booked_using_one_time_transfer__c, Previous_Booking__c
            FROM Opportunity WHERE AccountId = :accountId WITH USER_MODE
            ORDER BY Event_Date_and_Start_Time__c DESC NULLS LAST LIMIT :MAX_ROWS
        ];
        Set<Id> bookingIds = new Set<Id>();
        List<Object> bookingRows = new List<Object>();
        i = 1;
        for (Opportunity o : bookings) {
            String token = 'Booking ' + (i++);
            r.tokenToRecordId.put(token, o.Id);
            bookingIds.add(o.Id);
            bookingRows.add(new Map<String, Object>{
                'token' => token,
                'stage' => o.StageName,
                'amount' => o.Amount,
                'eventType' => o.Event_Type__c,
                'bookingType' => o.Booking_Type__c,
                'package' => o.Party_Package__c,
                'room' => o.Activity_Room__c,
                'eventDate' => o.Event_Date_and_Start_Time__c == null ? null : String.valueOf(o.Event_Date_and_Start_Time__c.date()),
                'estimatedChildren' => o.Estimated_Children__c,
                'estimatedAdults' => o.Estimated_Adults__c,
                'addOns' => Redactor.redact(o.Summary_of_Add_Ons__c, knownNames),
                'preferences' => Redactor.redact(o.Pizza_or_Add_on_Preferences__c, knownNames),
                'laserTag' => o.Laser_Tag__c,
                'cancellationReason' => o.Reason_for_Cancellation__c,
                'rebookedWithTransfer' => o.Party_Re_booked_using_one_time_transfer__c,
                'isRebooking' => o.Previous_Booking__c != null
            });
        }
        ctx.put('bookings', bookingRows);
        r.fieldsSent.addAll(new List<String>{
            'Opportunity.StageName', 'Opportunity.Amount', 'Opportunity.Event_Type__c', 'Opportunity.Booking_Type__c',
            'Opportunity.Party_Package__c', 'Opportunity.Activity_Room__c', 'Opportunity.Event_Date_and_Start_Time__c', 'Opportunity.Estimated_Children__c',
            'Opportunity.Estimated_Adults__c', 'Opportunity.Summary_of_Add_Ons__c (redacted)',
            'Opportunity.Pizza_or_Add_on_Preferences__c (redacted)', 'Opportunity.Laser_Tag__c',
            'Opportunity.Reason_for_Cancellation__c', 'Opportunity.Party_Re_booked_using_one_time_transfer__c',
            'Opportunity.Previous_Booking__c (as flag)'
        });

        List<Order> orders = [
            SELECT Id, EffectiveDate, Status, Total_Amount_with_Taxes__c, Invoice_Status__c, Laser_Tag_Package__c,
                   Number_of_Kids__c, Number_of_Adults__c, Refund_Amount__c
            FROM Order WHERE AccountId = :accountId WITH USER_MODE ORDER BY EffectiveDate DESC LIMIT :MAX_ROWS
        ];
        Set<Id> orderIds = new Set<Id>();
        List<Object> orderRows = new List<Object>();
        i = 1;
        for (Order o : orders) {
            String token = 'Order ' + (i++);
            r.tokenToRecordId.put(token, o.Id);
            orderIds.add(o.Id);
            orderRows.add(new Map<String, Object>{
                'token' => token,
                'date' => String.valueOf(o.EffectiveDate),
                'status' => o.Status,
                'total' => o.Total_Amount_with_Taxes__c,
                'invoiceStatus' => o.Invoice_Status__c,
                'laserTagPackage' => o.Laser_Tag_Package__c,
                'kids' => o.Number_of_Kids__c,
                'adults' => o.Number_of_Adults__c,
                'refund' => o.Refund_Amount__c
            });
        }
        ctx.put('orders', orderRows);
        r.fieldsSent.addAll(new List<String>{
            'Order.EffectiveDate', 'Order.Status', 'Order.Total_Amount_with_Taxes__c', 'Order.Invoice_Status__c',
            'Order.Laser_Tag_Package__c', 'Order.Number_of_Kids__c', 'Order.Number_of_Adults__c', 'Order.Refund_Amount__c'
        });

        List<Object> campRows = new List<Object>();
        if (!contactIds.isEmpty()) {
            for (Participant__c p : [
                SELECT Id, Status__c, Camp_Type__c, Registered_for__c, Lunch_Add_On__c, After_Care_Requested__c,
                       Camp_Class__r.Type__c, Camp_Class__r.Start_Date__c
                FROM Participant__c WHERE Primary_Parent_Contact__c IN :contactIds WITH USER_MODE
                ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
            ]) {
                String token = 'Camp ' + (campRows.size() + 1);
                r.tokenToRecordId.put(token, p.Id);
                campRows.add(new Map<String, Object>{
                    'token' => token,
                    'status' => p.Status__c,
                    'campType' => p.Camp_Type__c,
                    'classType' => p.Camp_Class__r?.Type__c,
                    'startDate' => p.Camp_Class__r?.Start_Date__c == null ? null : String.valueOf(p.Camp_Class__r.Start_Date__c),
                    'registeredFor' => p.Registered_for__c,
                    'lunchAddOn' => p.Lunch_Add_On__c,
                    'afterCare' => p.After_Care_Requested__c
                });
            }
        }
        ctx.put('camps', campRows);
        r.fieldsSent.addAll(new List<String>{
            'Participant__c.Status__c', 'Participant__c.Camp_Type__c', 'Participant__c.Registered_for__c',
            'Participant__c.Lunch_Add_On__c', 'Participant__c.After_Care_Requested__c', 'Camp__c.Type__c', 'Camp__c.Start_Date__c'
        });

        List<Object> noteRows = new List<Object>();
        if (!contactIds.isEmpty() || !bookingIds.isEmpty() || !orderIds.isEmpty()) {
            for (Team_notes__c n : [
                SELECT Id, Comments__c, Team_Member__c, CreatedDate
                FROM Team_notes__c
                WHERE Contact__c IN :contactIds OR Opportunity__c IN :bookingIds OR Order__c IN :orderIds
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
            ]) {
                String noteToken = 'Note ' + (noteRows.size() + 1);
                r.tokenToRecordId.put(noteToken, n.Id);
                noteRows.add(new Map<String, Object>{
                    'token' => noteToken,
                    'date' => String.valueOf(n.CreatedDate.date()),
                    'byTeamMember' => String.isNotBlank(n.Team_Member__c),
                    'text' => Redactor.redact(n.Comments__c, knownNames)
                });
            }
        }
        ctx.put('staffNotes', noteRows);
        r.fieldsSent.addAll(new List<String>{ 'Team_notes__c.Comments__c (redacted)', 'Team_notes__c.CreatedDate' });

        List<Object> activityRows = new List<Object>();
        Set<Id> whatIds = new Set<Id>(bookingIds);
        whatIds.add(accountId);
        Integer maxRows = MAX_ROWS;
        if (!contactIds.isEmpty() || !whatIds.isEmpty()) {
            for (Task t : [
                SELECT Subject, ActivityDate, Status, TaskSubtype, CreatedDate
                FROM Task
                WHERE WhoId IN :contactIds OR WhatId IN :whatIds
                WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT :maxRows
            ]) {
                activityRows.add(new Map<String, Object>{
                    'date' => String.valueOf(t.ActivityDate != null ? t.ActivityDate : t.CreatedDate.date()),
                    'subject' => Redactor.redact(t.Subject, knownNames),
                    'status' => t.Status,
                    'type' => t.TaskSubtype
                });
            }
        }
        ctx.put('activities', activityRows);
        r.fieldsSent.addAll(new List<String>{ 'Task.Subject (redacted)', 'Task.ActivityDate', 'Task.Status', 'Task.TaskSubtype' });

        List<Object> enquiryRows = new List<Object>();
        if (!emails.isEmpty() || !phones.isEmpty()) {
            for (Lead l : [
                SELECT Status, Party_Type__c, Booking_Type__c, Preferred_Date__c, Number_of_Kids__c, CreatedDate
                FROM Lead
                WHERE IsConverted = false AND (Email IN :emails OR Phone IN :phones)
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
            ]) {
                enquiryRows.add(new Map<String, Object>{
                    'received' => String.valueOf(l.CreatedDate.date()),
                    'status' => l.Status,
                    'partyType' => l.Party_Type__c,
                    'bookingType' => l.Booking_Type__c,
                    'preferredDate' => l.Preferred_Date__c == null ? null : String.valueOf(l.Preferred_Date__c),
                    'kids' => l.Number_of_Kids__c
                });
            }
        }
        ctx.put('openEnquiries', enquiryRows);
        r.fieldsSent.addAll(new List<String>{
            'Lead.Status', 'Lead.Party_Type__c', 'Lead.Booking_Type__c', 'Lead.Preferred_Date__c', 'Lead.Number_of_Kids__c'
        });

        List<Object> captured = new List<Object>();
        for (Family_Enquiry__c fe : [
            SELECT Id, CreatedDate, Enquiry_Type__c, Channel__c, Preferred_Date__c, Kids__c, Adults__c,
                   Package_Interest__c, Room_Preference__c, Add_Ons__c, Deposit_Discussed__c, Notes__c,
                   Follow_Up_Date__c, Booking__c, Changes__c, Draft_Status__c, Players__c, Pizza_Count__c
            FROM Family_Enquiry__c WHERE Account__c = :accountId WITH USER_MODE
            ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
        ]) {
            String token = 'Enquiry ' + (captured.size() + 1);
            r.tokenToRecordId.put(token, fe.Id);
            String bookingToken = null;
            for (String t : r.tokenToRecordId.keySet()) {
                if (fe.Booking__c != null && r.tokenToRecordId.get(t) == fe.Booking__c) { bookingToken = t; }
            }
            captured.add(new Map<String, Object>{
                'token' => token,
                'logged' => String.valueOf(fe.CreatedDate.date()),
                'type' => fe.Enquiry_Type__c,
                'channel' => fe.Channel__c,
                'preferredDate' => fe.Preferred_Date__c == null ? null : String.valueOf(fe.Preferred_Date__c),
                'kids' => fe.Kids__c,
                'adults' => fe.Adults__c,
                'package' => fe.Package_Interest__c,
                'room' => fe.Room_Preference__c,
                'addOns' => fe.Add_Ons__c,
                'depositDiscussed' => fe.Deposit_Discussed__c,
                'notes' => Redactor.redact(fe.Notes__c, knownNames),
                'followUpDate' => fe.Follow_Up_Date__c == null ? null : String.valueOf(fe.Follow_Up_Date__c),
                'aboutBooking' => bookingToken,
                'changes' => fe.Changes__c,
                'status' => fe.Draft_Status__c,
                'players' => fe.Players__c,
                'pizzas' => fe.Pizza_Count__c
            });
        }
        ctx.put('deskEnquiries', captured);
        r.fieldsSent.addAll(new List<String>{
            'Family_Enquiry__c (all fields except Allergy_Flagged__c; Notes__c redacted)'
        });

        r.contextJson = JSON.serialize(ctx, true);
        return r;
    }

    /**
     * Names are read ONLY to mask them in free text; they are never added to the context.
     * Includes minors' first and last names and party guest-of-honour names.
     */
    @TestVisible
    private static Set<String> collectKnownNames(Id accountId) {
        Set<String> names = new Set<String>();
        for (Contact c : [SELECT FirstName, LastName FROM Contact WHERE AccountId = :accountId WITH SYSTEM_MODE LIMIT 200]) {
            names.add(c.FirstName);
            names.add(c.LastName);
        }
        for (Minor__c m : [SELECT First_Name__c, Last_Name__c FROM Minor__c WHERE Account__c = :accountId WITH SYSTEM_MODE LIMIT 200]) {
            names.add(m.First_Name__c);
            names.add(m.Last_Name__c);
        }
        for (Opportunity o : [SELECT Special_Guest_s_Name__c FROM Opportunity WHERE AccountId = :accountId WITH SYSTEM_MODE LIMIT 200]) {
            if (String.isNotBlank(o.Special_Guest_s_Name__c)) {
                names.addAll(o.Special_Guest_s_Name__c.split('[\\s,&/\']+'));
            }
        }
        names.remove(null);
        return names;
    }

    private static String letter(Integer index) {
        String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        return index < 26 ? letters.substring(index, index + 1) : String.valueOf(index + 1);
    }
}
