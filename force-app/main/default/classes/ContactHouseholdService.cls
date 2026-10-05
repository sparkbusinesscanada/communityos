/**
 * Household (Account) for every Contact with a phone number.
 * Fun Circle convention: a household Account is named with the 10-digit phone (the existing
 * Before_Update_Insert flow links to it when it exists). This adds the missing half:
 *   - Contact has a phone and no Account -> link to the Account named with that phone, or create it.
 *   - Phone changes and the Contact sits in the household named with the OLD phone -> move to the new one.
 *   - Contacts on a named Account (e.g. a daycare) are never moved.
 * Changing AccountId does not push anything to Square (SquareTrigger only syncs name, email, phone).
 */
public without sharing class ContactHouseholdService {
    @TestVisible static Boolean running = false;

    public static String phoneKey(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String d = phone.replaceAll('[^0-9]', '');
        if (d.length() == 11 && d.startsWith('1')) {
            d = d.substring(1);
        }
        return d.length() == 10 ? d : null;
    }

    private static String keyOf(Contact c) {
        String k = phoneKey(c.Phone);
        return k != null ? k : phoneKey(c.MobilePhone);
    }

    public static Integer link(List<Contact> contacts, Map<Id, Contact> oldMap) {
        if (running) {
            return 0;
        }
        Map<Id, String> wanted = new Map<Id, String>();
        Map<Id, String> movedFrom = new Map<Id, String>();
        Set<Id> currentAccounts = new Set<Id>();
        for (Contact c : contacts) {
            String key = keyOf(c);
            if (key == null) {
                continue;
            }
            if (c.AccountId == null) {
                wanted.put(c.Id, key);
            } else if (oldMap != null && oldMap.containsKey(c.Id)) {
                String oldKey = keyOf(oldMap.get(c.Id));
                if (oldKey != null && oldKey != key) {
                    movedFrom.put(c.Id, oldKey);
                    currentAccounts.add(c.AccountId);
                }
            }
        }
        if (!movedFrom.isEmpty()) {
            Map<Id, Account> current = new Map<Id, Account>([SELECT Id, Name FROM Account WHERE Id IN :currentAccounts]);
            for (Contact c : contacts) {
                if (movedFrom.containsKey(c.Id) && current.containsKey(c.AccountId)
                        && current.get(c.AccountId).Name == movedFrom.get(c.Id)) {
                    wanted.put(c.Id, keyOf(c));
                }
            }
        }
        if (wanted.isEmpty()) {
            return 0;
        }

        Set<String> keys = new Set<String>(wanted.values());
        Map<String, Id> accountByKey = new Map<String, Id>();
        for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :keys ORDER BY CreatedDate ASC]) {
            if (!accountByKey.containsKey(a.Name)) {
                accountByKey.put(a.Name, a.Id);
            }
        }
        List<Account> toCreate = new List<Account>();
        for (String k : keys) {
            if (!accountByKey.containsKey(k)) {
                toCreate.add(new Account(Name = k, Phone = k));
            }
        }
        running = true;
        try {
            if (!toCreate.isEmpty()) {
                insert toCreate;
                for (Account a : toCreate) {
                    accountByKey.put(a.Name, a.Id);
                }
            }
            List<Contact> updates = new List<Contact>();
            for (Id cid : wanted.keySet()) {
                updates.add(new Contact(Id = cid, AccountId = accountByKey.get(wanted.get(cid))));
            }
            update updates;
            return updates.size();
        } finally {
            running = false;
        }
    }
}
