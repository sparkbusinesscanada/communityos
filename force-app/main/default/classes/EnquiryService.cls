/**
 * Guided desk conversation. Staff pick what the call is about and answer only the questions that are
 * NOT already known from Square / Salesforce history. The answers become:
 *   - a Family_Enquiry__c draft (always) + staff note + optional follow-up task
 *   - after staff confirm: a new Lead (new party), a Booking update (change), or an Order (laser tag / drop-in)
 *
 * Sandbox protection: Booking changes and Orders sync to live Square through existing automation, so they are
 * only applied when CommunityOS Settings > Allow Live Writes is on. A Lead is applied when live writes are on
 * or the org cannot send email (no customer can be emailed).
 */
public with sharing class EnquiryService {
    public static final String NEW_PARTY = 'New party';
    public static final String CHANGE_BOOKING = 'Change a booking';
    public static final String LASER_TAG = 'Laser tag';
    public static final String CAMP = 'Camp or class';
    public static final String DROP_IN = 'Drop-in';
    public static final String QUESTION = 'Just a question';

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class Options {
        @AuraEnabled public List<Option> intents = new List<Option>();
        @AuraEnabled public List<Option> channels = new List<Option>();
        @AuraEnabled public List<Option> addOns = new List<Option>();
        @AuraEnabled public List<Option> changes = new List<Option>();
        @AuraEnabled public List<Option> packages = new List<Option>();
        @AuraEnabled public List<Option> rooms = new List<Option>();
        @AuraEnabled public List<Option> times = new List<Option>();
        @AuraEnabled public List<Option> cancelReasons = new List<Option>();
        @AuraEnabled public List<Option> laserPackages = new List<Option>();
        @AuraEnabled public List<Option> visitFrequency = new List<Option>();
        @AuraEnabled public List<Option> heardAbout = new List<Option>();
        @AuraEnabled public List<Option> interests = new List<Option>();
        @AuraEnabled public List<Option> contactPrefs = new List<Option>();
    }

    public class EnquiryInput {
        @AuraEnabled public String enquiryType;
        @AuraEnabled public String channel;
        @AuraEnabled public Date preferredDate;
        @AuraEnabled public Date backupDate;
        @AuraEnabled public String preferredTime;
        @AuraEnabled public Integer kids;
        @AuraEnabled public Integer adults;
        @AuraEnabled public Integer pizzas;
        @AuraEnabled public Integer players;
        @AuraEnabled public String laserPackage;
        @AuraEnabled public String packageInterest;
        @AuraEnabled public String roomPreference;
        @AuraEnabled public List<String> addOns;
        @AuraEnabled public List<String> changes;
        @AuraEnabled public String cancelReason;
        @AuraEnabled public Boolean depositDiscussed;
        @AuraEnabled public Boolean allergyFlagged;
        @AuraEnabled public String notes;
        @AuraEnabled public Date followUpDate;
        @AuraEnabled public Id bookingId;
        @AuraEnabled public String teamMember;
    }

    public class DraftField {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public DraftField(String label, Object value) {
            this.label = label;
            this.value = value == null ? '' : String.valueOf(value);
        }
    }

    public class Draft {
        @AuraEnabled public Id enquiryId;
        @AuraEnabled public String target;
        @AuraEnabled public String actionLabel;
        @AuraEnabled public List<DraftField> fields = new List<DraftField>();
        @AuraEnabled public Boolean canApply = false;
        @AuraEnabled public String blockedReason;
        @AuraEnabled public String status;
        @AuraEnabled public Id appliedRecordId;
    }

    public static Options options() {
        Options o = new Options();
        o.intents = toOptions(Family_Enquiry__c.Enquiry_Type__c);
        o.channels = toOptions(Family_Enquiry__c.Channel__c);
        o.addOns = toOptions(Family_Enquiry__c.Add_Ons__c);
        o.changes = toOptions(Family_Enquiry__c.Changes__c);
        o.packages = toOptions(Opportunity.Party_Package__c);
        o.rooms = toOptions(Opportunity.Activity_Room__c);
        o.times = toOptions(Lead.Preferred_Time__c);
        o.cancelReasons = toOptions(Opportunity.Reason_for_Cancellation__c);
        o.laserPackages = toOptions(Order.Laser_Tag_Package__c);
        o.visitFrequency = toOptions(Account.Visit_Frequency__c);
        o.heardAbout = toOptions(Account.Heard_About_Us__c);
        o.interests = toOptions(Account.Interests__c);
        o.contactPrefs = toOptions(Account.Preferred_Contact__c);
        return o;
    }

    /** Validates and saves the conversation as a draft, a staff note and an optional follow-up task. */
    public static Draft save(Id accountId, EnquiryInput input) {
        validate(input);
        Id contactId = primaryContact(accountId);
        Family_Enquiry__c e = new Family_Enquiry__c(
            Account__c = accountId,
            Contact__c = contactId,
            Booking__c = input.bookingId,
            Enquiry_Type__c = input.enquiryType,
            Channel__c = input.channel,
            Preferred_Date__c = input.preferredDate,
            Backup_Date__c = input.backupDate,
            Preferred_Time__c = input.preferredTime,
            Kids__c = input.kids,
            Adults__c = input.adults,
            Pizza_Count__c = input.pizzas,
            Players__c = input.players,
            Laser_Tag_Package__c = input.laserPackage,
            Package_Interest__c = input.packageInterest,
            Room_Preference__c = input.roomPreference,
            Add_Ons__c = joinMulti(input.addOns),
            Changes__c = joinMulti(input.changes),
            Cancel_Reason__c = input.cancelReason,
            Deposit_Discussed__c = input.depositDiscussed == true,
            Allergy_Flagged__c = input.allergyFlagged == true,
            Notes__c = input.notes,
            Follow_Up_Date__c = input.followUpDate,
            Team_Member__c = input.teamMember,
            Draft_Status__c = targetFor(input.enquiryType) == null ? 'Note only' : 'Draft'
        );
        insert as user e;

        if (String.isNotBlank(input.notes) && contactId != null) {
            insert as user new Team_notes__c(
                Contact__c = contactId,
                Opportunity__c = input.bookingId,
                Team_Member__c = String.isBlank(input.teamMember) ? null : input.teamMember,
                Comments__c = '<p>' + (Datetime.now().format('d MMM yyyy') + ' - ' + input.enquiryType + ': ' + input.notes).escapeHtml4() + '</p>'
            );
        }
        if (input.followUpDate != null) {
            insert as user new Task(
                Subject = 'Follow up: ' + input.enquiryType,
                WhatId = e.Id,
                WhoId = contactId,
                ActivityDate = input.followUpDate,
                Status = 'Not Started',
                Priority = 'Normal',
                OwnerId = UserInfo.getUserId(),
                AI_Generated__c = false,
                AI_Reason__c = 'Logged in Family 360 conversation'
            );
        }
        return preview(e.Id);
    }

    /** What applying the draft would write, and whether it is allowed here. */
    public static Draft preview(Id enquiryId) {
        Family_Enquiry__c e = load(enquiryId);
        Draft d = new Draft();
        d.enquiryId = e.Id;
        d.status = e.Draft_Status__c;
        d.target = targetFor(e.Enquiry_Type__c);
        d.appliedRecordId = String.isBlank(e.Applied_Record_Id__c) ? null : (Id) e.Applied_Record_Id__c;
        if (d.target == null) {
            d.target = 'Staff note';
            d.actionLabel = null;
            d.fields.add(new DraftField('Saved as', 'Staff note' + (e.Follow_Up_Date__c == null ? '' : ' + follow-up task')));
            return d;
        }
        if (d.target == 'Lead') {
            d.actionLabel = 'Create party lead';
            d.fields.add(new DraftField('Party type', 'Birthday Party'));
            d.fields.add(new DraftField('Preferred date', e.Preferred_Date__c));
            d.fields.add(new DraftField('Backup date', e.Backup_Date__c));
            d.fields.add(new DraftField('Preferred time', e.Preferred_Time__c));
            d.fields.add(new DraftField('Kids / adults', nz(e.Kids__c) + ' / ' + nz(e.Adults__c)));
            d.fields.add(new DraftField('Package / room', blank(e.Package_Interest__c) + ' / ' + blank(e.Room_Preference__c)));
            d.fields.add(new DraftField('Add-ons', e.Add_Ons__c == null ? '' : e.Add_Ons__c.replace(';', ', ')));
            d.fields.add(new DraftField('Pizzas', e.Pizza_Count__c));
            d.fields.add(new DraftField('Lead source', leadSource(e.Channel__c)));
        } else if (d.target == 'Booking') {
            d.actionLabel = 'Apply to booking';
            Set<String> ch = splitMulti(e.Changes__c);
            if (e.Booking__c == null) {
                d.blockedReason = 'Pick which booking is changing.';
            }
            if (ch.contains('Cancel')) {
                d.fields.add(new DraftField('Stage', 'Closed Lost'));
                d.fields.add(new DraftField('Cancel reason', e.Cancel_Reason__c));
            }
            if (ch.contains('Date')) { d.fields.add(new DraftField('New date', e.Preferred_Date__c)); }
            if (ch.contains('Headcount')) { d.fields.add(new DraftField('Kids / adults', nz(e.Kids__c) + ' / ' + nz(e.Adults__c))); }
            if (ch.contains('Room')) { d.fields.add(new DraftField('Room', e.Room_Preference__c)); }
            if (ch.contains('Package')) { d.fields.add(new DraftField('Package', e.Package_Interest__c)); }
            if (ch.contains('Add-ons')) { d.fields.add(new DraftField('Add-ons (staff to price)', e.Add_Ons__c == null ? '' : e.Add_Ons__c.replace(';', ', '))); }
            if (ch.isEmpty()) { d.blockedReason = 'Choose what is changing.'; }
        } else {
            d.actionLabel = 'Create order';
            d.fields.add(new DraftField('Type', e.Enquiry_Type__c));
            d.fields.add(new DraftField('Date', e.Preferred_Date__c));
            if (e.Enquiry_Type__c == LASER_TAG) {
                d.fields.add(new DraftField('Players', e.Players__c));
                d.fields.add(new DraftField('Package', e.Laser_Tag_Package__c));
            } else {
                d.fields.add(new DraftField('Kids / adults', nz(e.Kids__c) + ' / ' + nz(e.Adults__c)));
            }
        }
        if (d.target == 'Order') {
            d.actionLabel = null;
            d.blockedReason = 'Finish this in Laser Tag Booking or at the POS: that screen creates the Square order and invoice.';
        }
        if (d.blockedReason == null) {
            d.blockedReason = sandboxBlock(d.target);
        }
        d.canApply = d.blockedReason == null && e.Draft_Status__c == 'Draft';
        return d;
    }

    /** Applies a confirmed draft. Returns the refreshed draft with the created / updated record id. */
    public static Draft apply(Id enquiryId) {
        Draft d = preview(enquiryId);
        Family_Enquiry__c e = load(enquiryId);
        if (e.Draft_Status__c != 'Draft') {
            throw new EnquiryException('This draft was already ' + e.Draft_Status__c.toLowerCase() + '.');
        }
        if (!d.canApply) {
            if (d.blockedReason != null && d.blockedReason.startsWith('Sandbox')) {
                update as user new Family_Enquiry__c(Id = e.Id, Draft_Status__c = 'Held in sandbox');
                return preview(enquiryId);
            }
            throw new EnquiryException(d.blockedReason);
        }
        Id written;
        if (d.target == 'Lead') {
            written = createLead(e);
        } else if (d.target == 'Booking') {
            written = updateBooking(e);
        } else {
            throw new EnquiryException(d.blockedReason);
        }
        update as user new Family_Enquiry__c(Id = e.Id, Draft_Status__c = 'Applied', Applied_To__c = d.target, Applied_Record_Id__c = written);
        return preview(enquiryId);
    }

    public static void discard(Id enquiryId) {
        update as user new Family_Enquiry__c(Id = enquiryId, Draft_Status__c = 'Discarded');
    }

    private static Id createLead(Family_Enquiry__c e) {
        Contact c = e.Contact__c == null ? null : [SELECT FirstName, LastName, Email, Phone, MobilePhone FROM Contact WHERE Id = :e.Contact__c WITH USER_MODE];
        Account a = [SELECT Name, Phone FROM Account WHERE Id = :e.Account__c WITH USER_MODE];
        Set<String> addOns = splitMulti(e.Add_Ons__c);
        List<String> prefs = new List<String>();
        if (e.Pizza_Count__c != null) { prefs.add(e.Pizza_Count__c.intValue() + ' pizzas'); }
        if (!addOns.isEmpty()) { prefs.add('Add-ons: ' + String.join(new List<String>(addOns), ', ')); }
        if (e.Backup_Date__c != null) { prefs.add('Backup date ' + String.valueOf(e.Backup_Date__c)); }
        if (String.isNotBlank(e.Package_Interest__c)) { prefs.add('Package ' + e.Package_Interest__c); }
        if (String.isNotBlank(e.Room_Preference__c)) { prefs.add('Room ' + e.Room_Preference__c); }
        Lead l = new Lead(
            FirstName = c?.FirstName,
            LastName = c != null && String.isNotBlank(c.LastName) ? c.LastName : a.Name,
            Company = a.Name,
            Email = c?.Email,
            Phone = c != null && String.isNotBlank(c.Phone) ? c.Phone : (c != null && String.isNotBlank(c.MobilePhone) ? c.MobilePhone : a.Phone),
            Status = 'Open',
            LeadSource = leadSource(e.Channel__c),
            Booking_Type__c = 'Party',
            Party_Type__c = 'Birthday Party',
            Preferred_Date__c = e.Preferred_Date__c,
            Preferred_Time__c = String.isBlank(e.Preferred_Time__c) ? null : e.Preferred_Time__c,
            Number_of_Kids__c = e.Kids__c,
            Number_of_Adults__c = e.Adults__c,
            Facepainter__c = addOns.contains('Face painting') ? 'Yes' : 'No',
            Pizza_Preference__c = String.join(prefs, '; ').left(255)
        );
        insert as user l;
        return l.Id;
    }

    private static Id updateBooking(Family_Enquiry__c e) {
        Opportunity o = [SELECT Id, Event_Date_and_Start_Time__c FROM Opportunity WHERE Id = :e.Booking__c WITH USER_MODE];
        Set<String> ch = splitMulti(e.Changes__c);
        if (ch.contains('Cancel')) {
            o.StageName = 'Closed Lost';
            o.Reason_for_Cancellation__c = e.Cancel_Reason__c;
        }
        if (ch.contains('Date') && e.Preferred_Date__c != null) {
            Time t = o.Event_Date_and_Start_Time__c == null ? Time.newInstance(12, 0, 0, 0) : o.Event_Date_and_Start_Time__c.time();
            o.Event_Date_and_Start_Time__c = Datetime.newInstance(e.Preferred_Date__c, t);
        }
        if (ch.contains('Headcount')) {
            o.Estimated_Children__c = e.Kids__c;
            o.Estimated_Adults__c = e.Adults__c;
        }
        if (ch.contains('Room') && String.isNotBlank(e.Room_Preference__c)) { o.Activity_Room__c = e.Room_Preference__c; }
        if (ch.contains('Package') && String.isNotBlank(e.Package_Interest__c)) { o.Party_Package__c = e.Package_Interest__c; }
        update as user o;
        return o.Id;
    }

    @TestVisible
    private static Boolean liveWritesOverride;
    @TestVisible
    private static Boolean emailOffOverride;

    @TestVisible
    private static String sandboxBlock(String target) {
        CommunityOS_Settings__c s = CommunityOS_Settings__c.getInstance();
        Boolean live = liveWritesOverride != null ? liveWritesOverride : (s != null && s.Allow_Live_Writes__c == true);
        if (live) {
            return null;
        }
        if (target == 'Lead') {
            Boolean emailOff = emailOffOverride != null ? emailOffOverride : emailDeliveryOff();
            return emailOff ? null : 'Sandbox protection: new leads email the family; turn on Allow Live Writes to create it.';
        }
        return 'Sandbox protection: ' + (target == 'Booking' ? 'booking changes' : 'orders') +
            ' sync to live Square. The draft is saved; apply it in production.';
    }

    private static Boolean emailDeliveryOff() {
        try {
            Messaging.reserveSingleEmailCapacity(1);
            return false;
        } catch (Exception ex) {
            return true;
        }
    }

    private static void validate(EnquiryInput input) {
        if (input == null || String.isBlank(input.enquiryType)) {
            throw new EnquiryException('Choose what the call is about.');
        }
        for (Integer n : new List<Integer>{ input.kids, input.adults, input.pizzas, input.players }) {
            if (n != null && (n < 0 || n > 500)) {
                throw new EnquiryException('Numbers must be between 0 and 500.');
            }
        }
        for (Date d : new List<Date>{ input.preferredDate, input.backupDate, input.followUpDate }) {
            if (d != null && d < Date.today()) {
                throw new EnquiryException('Dates cannot be in the past.');
            }
        }
        if (input.enquiryType == CHANGE_BOOKING && input.bookingId == null) {
            throw new EnquiryException('Pick which booking is changing.');
        }
        if (input.enquiryType == NEW_PARTY && input.preferredDate == null) {
            throw new EnquiryException('A new party needs a preferred date.');
        }
    }

    @TestVisible
    private static String targetFor(String intent) {
        if (intent == NEW_PARTY) { return 'Lead'; }
        if (intent == CHANGE_BOOKING) { return 'Booking'; }
        if (intent == LASER_TAG || intent == DROP_IN) { return 'Order'; }
        return null;
    }

    private static Family_Enquiry__c load(Id enquiryId) {
        return [
            SELECT Id, Account__c, Contact__c, Booking__c, Enquiry_Type__c, Channel__c, Preferred_Date__c, Backup_Date__c,
                   Preferred_Time__c, Kids__c, Adults__c, Pizza_Count__c, Players__c, Laser_Tag_Package__c, Package_Interest__c,
                   Room_Preference__c, Add_Ons__c, Changes__c, Cancel_Reason__c, Follow_Up_Date__c, Draft_Status__c,
                   Applied_To__c, Applied_Record_Id__c
            FROM Family_Enquiry__c WHERE Id = :enquiryId WITH USER_MODE
        ];
    }

    private static String leadSource(String channel) {
        if (channel == 'Phone') { return 'Phone'; }
        if (channel == 'Walk-in') { return 'Walk-in'; }
        if (channel == 'Email') { return 'Email'; }
        return 'Web';
    }

    private static String joinMulti(List<String> values) {
        return values == null || values.isEmpty() ? null : String.join(values, ';');
    }

    private static Set<String> splitMulti(String value) {
        return String.isBlank(value) ? new Set<String>() : new Set<String>(value.split(';'));
    }

    private static String nz(Decimal d) {
        return d == null ? '–' : String.valueOf(d.intValue());
    }

    private static String blank(String s) {
        return String.isBlank(s) ? '–' : s;
    }

    /** First contact on the household, else an existing billing contact from its bookings. */
    public static Id primaryContact(Id accountId) {
        for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :accountId WITH USER_MODE ORDER BY CreatedDate LIMIT 1]) {
            return c.Id;
        }
        Set<Id> billing = new Set<Id>();
        for (Opportunity o : [SELECT Billing_Contact__c FROM Opportunity WHERE AccountId = :accountId AND Billing_Contact__c != null
                              WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 5]) {
            billing.add(o.Billing_Contact__c);
        }
        for (Contact c : [SELECT Id FROM Contact WHERE Id IN :billing WITH USER_MODE LIMIT 1]) {
            return c.Id;
        }
        return null;
    }

    private static List<Option> toOptions(Schema.SObjectField f) {
        List<Option> out = new List<Option>();
        for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
            if (e.isActive()) { out.add(new Option(e.getLabel(), e.getValue())); }
        }
        return out;
    }

    public class EnquiryException extends Exception {}
}
