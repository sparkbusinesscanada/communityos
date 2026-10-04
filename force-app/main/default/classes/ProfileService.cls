/**
 * Family profile (asked once, only when unknown) and a computed Segment used to categorize families.
 * Segment rules are deterministic so staff can see why a family is tagged.
 */
public with sharing class ProfileService {
    public class Profile {
        @AuraEnabled public String visitFrequency;
        @AuraEnabled public String heardAbout;
        @AuraEnabled public List<String> interests = new List<String>();
        @AuraEnabled public String preferredContact;
        @AuraEnabled public String schoolDaycare;
        @AuraEnabled public String segment;
        @AuraEnabled public List<String> segments = new List<String>();
        @AuraEnabled public String updatedOn;
        @AuraEnabled public Integer unanswered = 0;
    }

    public class ProfileInput {
        @AuraEnabled public String visitFrequency;
        @AuraEnabled public String heardAbout;
        @AuraEnabled public List<String> interests;
        @AuraEnabled public String preferredContact;
        @AuraEnabled public String schoolDaycare;
    }

    public class Signals {
        public Integer partiesHosted = 0;
        public Integer bookings = 0;
        public Integer camps = 0;
        public Integer laserOrders = 0;
        public Date lastActivity;
        public Date customerSince;
        public Integer visitsLast90Days = 0;
        public Date lastVisit;

        public void addVisits(VisitSummaryService.Summary v) {
            if (v == null) { return; }
            visitsLast90Days = v.visitsLast90Days == null ? 0 : v.visitsLast90Days;
            lastVisit = v.lastVisitDate;
            if (lastVisit != null && (lastActivity == null || lastVisit > lastActivity)) { lastActivity = lastVisit; }
        }
    }

    public static Profile read(Account a, Signals sig) {
        Profile p = new Profile();
        p.visitFrequency = a.Visit_Frequency__c;
        p.heardAbout = a.Heard_About_Us__c;
        p.interests = String.isBlank(a.Interests__c) ? new List<String>() : a.Interests__c.split(';');
        p.preferredContact = a.Preferred_Contact__c;
        p.schoolDaycare = a.School_Daycare__c;
        p.updatedOn = a.Profile_Updated__c == null ? null : Datetime.newInstance(a.Profile_Updated__c, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy');
        p.segments = segmentsFor(a.Visit_Frequency__c, p.interests, a.School_Daycare__c, sig);
        p.segment = String.join(p.segments, ' · ');
        for (Object v : new List<Object>{ p.visitFrequency, p.heardAbout, p.preferredContact }) {
            if (v == null) { p.unanswered++; }
        }
        if (p.interests.isEmpty()) { p.unanswered++; }
        return p;
    }

    public static void save(Id accountId, ProfileInput input, Signals sig) {
        if (input == null) {
            throw new ProfileException('Nothing to save.');
        }
        Account a = new Account(
            Id = accountId,
            Visit_Frequency__c = blankToNull(input.visitFrequency),
            Heard_About_Us__c = blankToNull(input.heardAbout),
            Interests__c = input.interests == null || input.interests.isEmpty() ? null : String.join(input.interests, ';'),
            Preferred_Contact__c = blankToNull(input.preferredContact),
            School_Daycare__c = String.isBlank(input.schoolDaycare) ? null : input.schoolDaycare.trim().left(120),
            Profile_Updated__c = Date.today()
        );
        a.Segment__c = String.join(segmentsFor(a.Visit_Frequency__c,
            input.interests == null ? new List<String>() : input.interests, a.School_Daycare__c, sig), ' · ').left(120);
        update as user a;
    }

    @TestVisible
    private static List<String> segmentsFor(String frequency, List<String> interests, String school, Signals sig) {
        Set<String> i = new Set<String>(interests);
        List<String> out = new List<String>();
        Date today = Date.today();
        if (sig.customerSince != null && sig.customerSince.daysBetween(today) <= 30) {
            out.add('New family');
        }
        if (sig.partiesHosted >= 2) {
            out.add('Repeat party family');
        } else if (sig.partiesHosted == 1 || i.contains('Birthday parties')) {
            out.add('Party family');
        }
        if (sig.camps > 0 || i.contains('Camps and classes')) {
            out.add('Camp family');
        }
        if (sig.laserOrders > 0 || i.contains('Laser tag')) {
            out.add('Laser tag');
        }
        if (frequency == 'Weekly' || frequency == 'Monthly' || sig.visitsLast90Days >= 3) {
            out.add('Regular visitor');
        }
        if (String.isNotBlank(school)) {
            out.add('School / daycare link');
        }
        if (sig.lastActivity != null && sig.lastActivity.daysBetween(today) > 180) {
            out.add('Lapsed');
        }
        if (out.isEmpty()) {
            out.add('Not enough info yet');
        }
        return out;
    }

    private static String blankToNull(String s) {
        return String.isBlank(s) ? null : s;
    }

    public class ProfileException extends Exception {}
}
