/**
 * Loads Square customers into Salesforce without re-triggering the Square sync
 * (they already exist in Square). Households are created by ContactHouseholdService.
 * Input: JSON list of {squareId, firstName, lastName, email, phone, contactId}.
 * contactId present = update that Contact; absent = insert.
 */
public without sharing class CustomerImport {
    public class Row {
        public String contactId;
        public String squareId;
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
    }

    public static Map<String, Integer> load(String rowsJson) {
        List<Row> rows = (List<Row>) JSON.deserialize(rowsJson, List<Row>.class);
        List<Contact> inserts = new List<Contact>();
        List<Contact> updates = new List<Contact>();
        for (Row r : rows) {
            Contact c = new Contact(
                FirstName = r.firstName,
                LastName = String.isBlank(r.lastName) ? (String.isBlank(r.firstName) ? 'Unknown' : r.firstName) : r.lastName,
                Square_Id__c = r.squareId
            );
            if (String.isNotBlank(r.email)) { c.Email = r.email; }
            if (String.isNotBlank(r.phone)) { c.Phone = r.phone; }
            if (String.isNotBlank(r.contactId)) {
                c.Id = r.contactId;
                updates.add(c);
            } else {
                inserts.add(c);
            }
        }
        Map<String, Integer> out = new Map<String, Integer>{ 'inserted' => 0, 'updated' => 0, 'failed' => 0 };
        SquareIntegrationService.isProcessingSquareSync = true;
        try {
            for (Database.SaveResult s : Database.insert(inserts, false)) {
                if (s.isSuccess()) { out.put('inserted', out.get('inserted') + 1); } else { out.put('failed', out.get('failed') + 1); }
            }
            for (Database.SaveResult s : Database.update(updates, false)) {
                if (s.isSuccess()) { out.put('updated', out.get('updated') + 1); } else { out.put('failed', out.get('failed') + 1); }
            }
        } finally {
            SquareIntegrationService.isProcessingSquareSync = false;
        }
        return out;
    }
}
