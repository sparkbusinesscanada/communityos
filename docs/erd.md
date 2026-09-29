# Family Graph — ERD (v0.1, D02)

Tenant = one Salesforce org. Every fact is either native to the org (its record URL is the source_ref) or carries its source system's id plus Source_URL__c.

```mermaid
erDiagram
    ACCOUNT_HOUSEHOLD ||--o{ CONTACT : "guardians (AccountId)"
    ACCOUNT_HOUSEHOLD ||--o{ MINOR__C : "children (Account__c)"
    CONTACT ||--o{ MINOR__C : "Primary_Contact_from_Registration__c"
    ACCOUNT_HOUSEHOLD ||--o{ OPPORTUNITY_BOOKING : "party bookings"
    CONTACT ||--o{ PARTICIPANT__C : "camp registrations"
    CAMP__C ||--o{ PARTICIPANT__C : "Camp_Class__c"
    ACCOUNT_HOUSEHOLD ||--o{ CHECK_IN__C : "legacy check-ins"
    MINOR__C ||--o{ CHECK_IN__C : ""
    ACCOUNT_HOUSEHOLD ||--o{ VISIT__C : "Household__c"
    CONTACT ||--o{ VISIT__C : "paying guardian"
    MINOR__C ||--o{ VISIT__C : "child"
    ACCOUNT_HOUSEHOLD ||--o{ ENQUIRY__C : "Household__c"
    CONTACT ||--o{ ENQUIRY__C : "Contact__c"
    CONTACT ||--o{ WAIVER__C : "signing guardian"
    MINOR__C ||--o{ WAIVER__C : "child"
    CONTACT ||--o{ DESK_QUESTION__C : "asked by"
    DESK_QUESTION__C ||--o{ AGENT_EVENT__C : "agent calls"
    CONTACT ||--o{ MERGE_CANDIDATE__C : "Contact_A__c / Contact_B__c"

    ACCOUNT_HOUSEHOLD {
        RecordType Household
    }
    CONTACT {
        picklist Household_Role__c "Primary Guardian | Guardian | Other Adult"
        text Square_Id__c "ext id, unique (existing)"
        formula Source_System__c "Square if Square_Id__c else Salesforce"
        formula Source_URL__c "Square customer deep link"
        checkbox Authorized_to_Pick_Up__c "existing"
    }
    MINOR__C {
        checkbox Any_allergies_food_meds_etc__c "existing flag"
        checkbox Any_chronic_or_health_conditions__c "existing flag"
        checkbox Is_currently_taking_any_medication__c "existing flag"
        formula Has_Pickup_Restriction__c "new, derived from Unauthorized_Person__c"
    }
    VISIT__C {
        text Square_Order_Id__c "ext id, unique"
        datetime Visited_At__c
        currency Amount__c
        picklist Offering__c
        picklist Source_System__c
        url Source_URL__c
    }
    ENQUIRY__C {
        text Gmail_Message_Id__c "ext id, unique"
        text Gmail_Thread_Id__c
        datetime Received_At__c
        picklist Status__c
        picklist Source_System__c
        url Source_URL__c
    }
    WAIVER__C {
        text Drive_File_Id__c "ext id, unique"
        date Signed_On__c
        date Expires_On__c
        picklist Source_System__c
        url Source_URL__c
    }
    DESK_QUESTION__C {
        datetime Asked_At__c
        longtext Question__c
        picklist Offering__c
        checkbox Resolved_On_Spot__c
        checkbox Escalated_To_Owner__c
        checkbox Answered_By_Agent__c
    }
    MERGE_CANDIDATE__C {
        text Pair_Key__c "ext id, unique"
        number Match_Score__c
        picklist Status__c
    }
    AGENT_EVENT__C {
        picklist Agent__c
        longtext Request__c
        longtext Response__c
        longtext Source_Refs__c
        number Input_Tokens__c
        number Output_Tokens__c
    }
```

## Object map

| Graph concept | Salesforce object | New or existing | Source | Upsert key |
|---|---|---|---|---|
| Household | Account (RecordType Household) | existing object, new RT | Salesforce | Id |
| Guardian / adult | Contact | existing (+3 fields) | Square or Salesforce | Square_Id__c |
| Child | Minor__c | existing (+1 formula) | Salesforce | Id |
| Party booking | Opportunity (label "Booking") | existing | Salesforce | Booking_Reference__c |
| Camp registration | Participant__c → Camp__c | existing | Salesforce | Id |
| Legacy check-in | Check_In__c | existing | Salesforce | Id |
| Visit | Visit__c | new | Square | Square_Order_Id__c |
| Enquiry | Enquiry__c | new | Gmail | Gmail_Message_Id__c |
| Waiver | Waiver__c | new | Google Drive | Drive_File_Id__c |
| Desk tally | Desk_Question__c | new | Salesforce | Id |
| Identity review | Merge_Candidate__c | new | Salesforce (Apex batch) | Pair_Key__c |
| Agent audit | Agent_Event__c | new | agent runtime | Id |

## Provenance rule
- Visit__c, Enquiry__c, Waiver__c: validation rule Source_Refs_Required. Any Source_System__c other than Salesforce (including blank) needs Source_URL__c, and the system-specific id (Square_Order_Id__c, Gmail_Message_Id__c, Drive_File_Id__c).
- Contact: provenance is derived by formula from Square_Id__c, so all existing contacts are covered without backfill or changes to the Square sync.
- Native objects: the MCP server returns `{instanceUrl}/{Id}` as the source_ref.

## What agents can read (CommunityOS_Graph_Read)
Read-only with View All on the 13 graph objects. The following fields are **not** visible: Minor__c.Medical_Information__c, BC_Care_Card__c, Unauthorized_Person__c, Gender__c, vaccination and surgery fields; Contact Details_About_* and Medical_* notes; verification codes. Agents see the flags (allergy, medication, pickup restriction) and must send staff to the record for details.
