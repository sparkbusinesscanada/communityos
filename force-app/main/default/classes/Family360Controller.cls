/**
 * Server side of the Family 360 tab: search, household view (real data, staff only),
 * AI insights (pseudonymized, via FamilyInsightService), and staff actions (task, note).
 */
public with sharing class Family360Controller {
    private static final Integer ROWS = 25;

    public class HouseholdHit {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String people;
        @AuraEnabled public Decimal bookings;
    }

    public class Row {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String badge;
        @AuraEnabled public String body;
        public Row(Id id, String title, String subtitle, String dateLabel, String badge) {
            this.id = id;
            this.title = title;
            this.subtitle = subtitle;
            this.dateLabel = dateLabel;
            this.badge = badge;
        }
    }

    public class Household {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String customerSince;
        @AuraEnabled public Decimal bookingCount;
        @AuraEnabled public Decimal partiesHosted;
        @AuraEnabled public Id primaryContactId;
        @AuraEnabled public List<Row> people = new List<Row>();
        @AuraEnabled public List<Row> bookings = new List<Row>();
        @AuraEnabled public List<Row> orders = new List<Row>();
        @AuraEnabled public List<Row> camps = new List<Row>();
        @AuraEnabled public List<Row> notes = new List<Row>();
        @AuraEnabled public List<Row> openTasks = new List<Row>();
        @AuraEnabled public List<String> teamMembers = new List<String>();
        @AuraEnabled public List<Row> deskHistory = new List<Row>();
        @AuraEnabled public List<Row> enquiries = new List<Row>();
        @AuraEnabled public ProfileService.Profile profile;
        @AuraEnabled public List<EnquiryService.Option> recordOptions = new List<EnquiryService.Option>();
        @AuraEnabled public List<EnquiryService.Option> bookingOptions = new List<EnquiryService.Option>();
        @AuraEnabled public Decimal lifetimeSpend = 0;
        @AuraEnabled public Integer unpaidOrders = 0;
        @AuraEnabled public String nextEvent;
        @AuraEnabled public String lastEvent;
    }

    @AuraEnabled(cacheable=true)
    public static List<HouseholdHit> searchHouseholds(String term) {
        List<HouseholdHit> hits = new List<HouseholdHit>();
        String t = term == null ? '' : term.trim();
        if (t.length() < 3) {
            return hits;
        }
        String scope = t.contains('@') ? 'EMAIL FIELDS' : (t.replaceAll('[^0-9]', '').length() >= 7 ? 'PHONE FIELDS' : 'NAME FIELDS');
        String sosl = 'FIND :t IN ' + scope + ' RETURNING Account(Id), Contact(AccountId) LIMIT 50';
        List<List<SObject>> found = Search.query(sosl, AccessLevel.USER_MODE);

        Set<Id> accountIds = new Set<Id>();
        for (SObject a : found[0]) { accountIds.add(a.Id); }
        for (SObject c : found[1]) {
            Id aid = (Id) c.get('AccountId');
            if (aid != null) { accountIds.add(aid); }
        }
        if (accountIds.isEmpty()) {
            return hits;
        }
        for (Account a : [
            SELECT Id, Name, Phone, Number_of_Bookings__c,
                   (SELECT FirstName, LastName FROM Contacts ORDER BY CreatedDate LIMIT 3)
            FROM Account WHERE Id IN :accountIds WITH USER_MODE
            ORDER BY LastModifiedDate DESC LIMIT 15
        ]) {
            HouseholdHit h = new HouseholdHit();
            h.accountId = a.Id;
            h.name = a.Name;
            h.phone = a.Phone;
            h.bookings = a.Number_of_Bookings__c;
            List<String> names = new List<String>();
            for (Contact c : a.Contacts) { names.add(((c.FirstName == null ? '' : c.FirstName + ' ') + c.LastName).trim()); }
            h.people = String.join(names, ', ');
            hits.add(h);
        }
        return hits;
    }

    @AuraEnabled
    public static Household getHousehold(Id accountId) {
        Household h = new Household();
        Account a = [
            SELECT Id, Name, Phone, CreatedDate, Number_of_Bookings__c, of_Parties_Hosted__c,
                   Visit_Frequency__c, Heard_About_Us__c, Interests__c, Preferred_Contact__c, School_Daycare__c,
                   Segment__c, Profile_Updated__c
            FROM Account WHERE Id = :accountId WITH USER_MODE
        ];
        ProfileService.Signals sig = new ProfileService.Signals();
        sig.partiesHosted = a.of_Parties_Hosted__c == null ? 0 : a.of_Parties_Hosted__c.intValue();
        sig.customerSince = a.CreatedDate.date();
        h.accountId = a.Id;
        h.name = a.Name;
        h.phone = a.Phone;
        h.customerSince = a.CreatedDate.format('MMM yyyy');
        h.bookingCount = a.Number_of_Bookings__c;
        h.partiesHosted = a.of_Parties_Hosted__c;

        Set<Id> contactIds = new Set<Id>();
        for (Contact c : [
            SELECT Id, Name, Email, Phone, MobilePhone, Relationship__c
            FROM Contact WHERE AccountId = :accountId WITH USER_MODE ORDER BY CreatedDate LIMIT :ROWS
        ]) {
            contactIds.add(c.Id);
            if (h.primaryContactId == null) { h.primaryContactId = c.Id; }
            h.people.add(new Row(c.Id, c.Name, joinNonBlank(new List<String>{ c.Email, c.Phone != null ? c.Phone : c.MobilePhone }, ' · '), null, c.Relationship__c));
        }

        Set<Id> bookingIds = new Set<Id>();
        for (Opportunity o : [
            SELECT Id, Name, StageName, Amount, Event_Date_and_Start_Time__c, Party_Package__c, Activity_Room__c, Booking_Type__c
            FROM Opportunity WHERE AccountId = :accountId WITH USER_MODE
            ORDER BY Event_Date_and_Start_Time__c DESC NULLS LAST LIMIT :ROWS
        ]) {
            bookingIds.add(o.Id);
            sig.bookings++;
            if (o.Event_Date_and_Start_Time__c != null && o.Event_Date_and_Start_Time__c.date() <= Date.today()
                && (sig.lastActivity == null || o.Event_Date_and_Start_Time__c.date() > sig.lastActivity)) {
                sig.lastActivity = o.Event_Date_and_Start_Time__c.date();
            }
            String optLabel = o.Name + (o.Event_Date_and_Start_Time__c == null ? '' : ' (' + o.Event_Date_and_Start_Time__c.format('d MMM yyyy') + ')');
            h.recordOptions.add(new EnquiryService.Option('Booking: ' + optLabel, o.Id));
            h.bookingOptions.add(new EnquiryService.Option(optLabel, o.Id));
            if (o.Event_Date_and_Start_Time__c != null) {
                String label = o.Event_Date_and_Start_Time__c.format('d MMM yyyy');
                if (o.Event_Date_and_Start_Time__c >= Datetime.now()) { h.nextEvent = label; }
                else if (h.lastEvent == null) { h.lastEvent = label; }
            }
            h.bookings.add(new Row(o.Id, o.Name,
                joinNonBlank(new List<String>{ o.Booking_Type__c, o.Party_Package__c, o.Activity_Room__c, o.Amount == null ? null : '$' + o.Amount.setScale(2) }, ' · '),
                o.Event_Date_and_Start_Time__c == null ? null : o.Event_Date_and_Start_Time__c.format('EEE d MMM yyyy'),
                o.StageName));
        }

        Set<Id> orderIds = new Set<Id>();
        for (Order o : [
            SELECT Id, OrderNumber, EffectiveDate, Status, Total_Amount_with_Taxes__c, Invoice_Status__c, Laser_Tag_Package__c
            FROM Order WHERE AccountId = :accountId WITH USER_MODE ORDER BY EffectiveDate DESC LIMIT :ROWS
        ]) {
            orderIds.add(o.Id);
            h.recordOptions.add(new EnquiryService.Option('Order ' + o.OrderNumber + (o.Invoice_Status__c == null ? '' : ' · ' + o.Invoice_Status__c), o.Id));
            if (o.Invoice_Status__c == 'PAID' && o.Total_Amount_with_Taxes__c != null) { h.lifetimeSpend += o.Total_Amount_with_Taxes__c; }
            if (o.Laser_Tag_Package__c != null) { sig.laserOrders++; }
            if (o.EffectiveDate != null && o.EffectiveDate <= Date.today() && (sig.lastActivity == null || o.EffectiveDate > sig.lastActivity)) { sig.lastActivity = o.EffectiveDate; }
            if (o.Invoice_Status__c != null && o.Invoice_Status__c != 'PAID' && o.Status != 'Draft') { h.unpaidOrders++; }
            h.orders.add(new Row(o.Id, 'Order ' + o.OrderNumber,
                joinNonBlank(new List<String>{ o.Total_Amount_with_Taxes__c == null ? null : '$' + o.Total_Amount_with_Taxes__c.setScale(2), o.Laser_Tag_Package__c }, ' · '),
                o.EffectiveDate == null ? null : Datetime.newInstance(o.EffectiveDate, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy'),
                o.Invoice_Status__c != null ? o.Invoice_Status__c : o.Status));
        }

        if (!contactIds.isEmpty()) {
            for (Participant__c p : [
                SELECT Id, Status__c, Camp_Type__c, Camp_Class__r.Name, Camp_Class__r.Start_Date__c
                FROM Participant__c WHERE Primary_Parent_Contact__c IN :contactIds WITH USER_MODE
                ORDER BY CreatedDate DESC LIMIT :ROWS
            ]) {
                h.camps.add(new Row(p.Id, p.Camp_Class__r?.Name == null ? 'Camp registration' : p.Camp_Class__r.Name,
                    p.Camp_Type__c,
                    p.Camp_Class__r?.Start_Date__c == null ? null : Datetime.newInstance(p.Camp_Class__r.Start_Date__c, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy'),
                    p.Status__c));
            }
        }

        for (Team_notes__c n : [
            SELECT Id, Comments__c, Team_Member__c, CreatedDate, CreatedBy.Name
            FROM Team_notes__c
            WHERE Contact__c IN :contactIds OR Opportunity__c IN :bookingIds OR Order__c IN :orderIds
            WITH USER_MODE ORDER BY CreatedDate DESC LIMIT :ROWS
        ]) {
            Row r = new Row(n.Id, n.Team_Member__c != null ? n.Team_Member__c : n.CreatedBy.Name, null, n.CreatedDate.format('d MMM yyyy'), null);
            r.body = n.Comments__c == null ? '' : n.Comments__c.stripHtmlTags();
            h.notes.add(r);
        }

        Set<Id> whatIds = new Set<Id>(bookingIds);
        whatIds.add(accountId);
        Integer rows = ROWS;
        List<Task> openTasks = [
            SELECT Id, Subject, ActivityDate, AI_Generated__c, AI_Reason__c, Owner.Name
            FROM Task
            WHERE IsClosed = false AND (WhoId IN :contactIds OR WhatId IN :whatIds)
            ORDER BY ActivityDate ASC NULLS LAST LIMIT :rows
        ];
        for (SObject so : Security.stripInaccessible(AccessType.READABLE, openTasks).getRecords()) {
            Task t = (Task) so;
            Boolean ai = so.getPopulatedFieldsAsMap().containsKey('AI_Generated__c') && t.AI_Generated__c;
            Row r = new Row(t.Id, t.Subject, t.Owner?.Name,
                t.ActivityDate == null ? null : Datetime.newInstance(t.ActivityDate, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy'),
                ai ? 'AI' : null);
            r.body = so.getPopulatedFieldsAsMap().containsKey('AI_Reason__c') ? t.AI_Reason__c : null;
            h.openTasks.add(r);
        }

        for (Family_Enquiry__c fe : [
            SELECT Id, Enquiry_Type__c, Channel__c, Preferred_Date__c, Kids__c, Add_Ons__c, Changes__c, Notes__c,
                   CreatedDate, Draft_Status__c, Applied_To__c
            FROM Family_Enquiry__c WHERE Account__c = :accountId WITH USER_MODE ORDER BY CreatedDate DESC LIMIT :ROWS
        ]) {
            List<String> bits = new List<String>();
            if (fe.Channel__c != null) { bits.add(fe.Channel__c); }
            if (fe.Preferred_Date__c != null) { bits.add('for ' + Datetime.newInstance(fe.Preferred_Date__c, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy')); }
            if (fe.Kids__c != null) { bits.add(fe.Kids__c.intValue() + ' kids'); }
            if (fe.Changes__c != null) { bits.add('change: ' + fe.Changes__c.replace(';', ', ')); }
            if (fe.Add_Ons__c != null) { bits.add(fe.Add_Ons__c.replace(';', ', ')); }
            String status = fe.Draft_Status__c == 'Applied' && fe.Applied_To__c != null ? 'Applied to ' + fe.Applied_To__c : fe.Draft_Status__c;
            Row r = new Row(fe.Id, fe.Enquiry_Type__c, String.join(bits, ' · '), fe.CreatedDate.format('d MMM yyyy'), status);
            r.body = fe.Notes__c;
            h.enquiries.add(r);
        }

        for (Desk_Question__c dq : [
            SELECT Id, Question__c, Answer__c, Answer_Status__c, Source_Records__c, Asked_At__c,
                   Resolved_On_Spot__c, Escalated_To_Owner__c
            FROM Desk_Question__c WHERE Account__c = :accountId WITH USER_MODE
            ORDER BY Asked_At__c DESC LIMIT 10
        ]) {
            String outcome = dq.Resolved_On_Spot__c ? 'Resolved' : (dq.Escalated_To_Owner__c ? 'Escalated' : dq.Answer_Status__c);
            Row r = new Row(dq.Id, dq.Question__c, dq.Source_Records__c == null ? null : 'Sources: ' + dq.Source_Records__c,
                dq.Asked_At__c == null ? null : dq.Asked_At__c.format('d MMM, h:mm a'), outcome);
            r.body = dq.Answer__c;
            h.deskHistory.add(r);
        }

        sig.camps = h.camps.size();
        h.profile = ProfileService.read(a, sig);

        for (Schema.PicklistEntry e : Team_notes__c.Team_Member__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) { h.teamMembers.add(e.getValue()); }
        }
        return h;
    }

    @AuraEnabled(cacheable=true)
    public static List<DeskAgentService.Question> getDeskQuestions() {
        return DeskAgentService.templates();
    }

    @AuraEnabled(cacheable=true)
    public static EnquiryService.Options getEnquiryOptions() {
        return EnquiryService.options();
    }

    @AuraEnabled
    public static EnquiryService.Draft saveEnquiry(Id accountId, String inputJson) {
        try {
            EnquiryService.EnquiryInput input = String.isBlank(inputJson)
                ? null
                : (EnquiryService.EnquiryInput) JSON.deserialize(inputJson, EnquiryService.EnquiryInput.class);
            return EnquiryService.save(accountId, input);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static EnquiryService.Draft applyEnquiry(Id enquiryId) {
        try {
            return EnquiryService.apply(enquiryId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void discardEnquiry(Id enquiryId) {
        try {
            EnquiryService.discard(enquiryId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveProfile(Id accountId, String profileJson) {
        try {
            ProfileService.ProfileInput input = String.isBlank(profileJson)
                ? null
                : (ProfileService.ProfileInput) JSON.deserialize(profileJson, ProfileService.ProfileInput.class);
            Household h = getHousehold(accountId);
            ProfileService.Signals sig = new ProfileService.Signals();
            sig.partiesHosted = h.partiesHosted == null ? 0 : h.partiesHosted.intValue();
            sig.bookings = h.bookings.size();
            sig.camps = h.camps.size();
            ProfileService.save(accountId, input, sig);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static VisitSummaryService.Summary getVisitSummary(Id accountId) {
        try {
            return VisitSummaryService.get(accountId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static DeskAgentService.DeskResult askDesk(Id accountId, List<String> keys, String customQuestion, Id focusRecordId) {
        try {
            return DeskAgentService.ask(accountId, keys, customQuestion, focusRecordId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void markDeskOutcome(Id deskQuestionId, String outcome) {
        try {
            DeskAgentService.markOutcome(deskQuestionId, outcome);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static FamilyInsightService.InsightResult getInsights(Id accountId) {
        try {
            return FamilyInsightService.run(accountId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id createTask(Id accountId, String subject, String reason, Integer dueInDays, Id relatedRecordId, Id logId) {
        try {
            Task t = new Task(
                Subject = subject.left(255),
                AI_Reason__c = reason,
                AI_Generated__c = logId != null,
                AI_Call_Log__c = logId,
                ActivityDate = Date.today().addDays(dueInDays == null ? 2 : dueInDays),
                Status = 'Not Started',
                Priority = 'Normal',
                OwnerId = UserInfo.getUserId()
            );
            String related = relatedRecordId == null ? null : relatedRecordId.getSObjectType().getDescribe().getName();
            if (related == 'Contact') {
                t.WhoId = relatedRecordId;
                t.WhatId = accountId;
            } else {
                t.WhatId = (related == 'Opportunity' || related == 'Order' || related == 'Account') ? relatedRecordId : accountId;
                List<Contact> primary = [SELECT Id FROM Contact WHERE AccountId = :accountId WITH USER_MODE ORDER BY CreatedDate LIMIT 1];
                if (!primary.isEmpty()) { t.WhoId = primary[0].Id; }
            }
            insert as user t;

            if (logId != null) {
                AI_Call_Log__c log = [SELECT Id, Tasks_Created__c FROM AI_Call_Log__c WHERE Id = :logId WITH SYSTEM_MODE];
                log.Tasks_Created__c = (log.Tasks_Created__c == null ? 0 : log.Tasks_Created__c) + 1;
                update as system log;
            }
            return t.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id addNote(Id accountId, Id contactId, String text, String teamMember) {
        if (String.isBlank(text)) {
            throw new AuraHandledException('Write a note first.');
        }
        try {
            Id cid = contactId;
            if (cid == null) {
                List<Contact> primary = [SELECT Id FROM Contact WHERE AccountId = :accountId WITH USER_MODE ORDER BY CreatedDate LIMIT 1];
                if (primary.isEmpty()) {
                    throw new AuraHandledException('This household has no contact to attach the note to.');
                }
                cid = primary[0].Id;
            }
            String stamp = Datetime.now().format('d MMM yyyy') + ' - ';
            Team_notes__c n = new Team_notes__c(
                Contact__c = cid,
                Team_Member__c = String.isBlank(teamMember) ? null : teamMember,
                Comments__c = '<p>' + (stamp + text).escapeHtml4().replace('\n', '<br>') + '</p>'
            );
            insert as user n;
            return n.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String joinNonBlank(List<String> parts, String sep) {
        List<String> keep = new List<String>();
        for (String p : parts) {
            if (String.isNotBlank(p)) { keep.add(p); }
        }
        return String.join(keep, sep);
    }
}
