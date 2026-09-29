# CommunityOS MVP — Data Map (COS sandbox)

Source: live schema of `cos` sandbox (00DAs00000yfdkPMAQ), mapped 27 Sep 2026.
COS holds a copy of production data: treat every record as real customer data.

## Family graph

| Concept | Object | Key link |
|---|---|---|
| Household | Account | Phone (search key) |
| Parent / adult | Contact | AccountId, Email, Phone, Square_Id__c |
| Party / event booking | Opportunity (label: Booking) | AccountId, Billing_Contact__c, Event_Date_and_Start_Time__c |
| Square order / invoice | Order | AccountId, Order_Square_Id__c, Invoice_Square_Id__c |
| Web party request | Lead | Email, Phone, Preferred_Date__c |
| Camp registration | Participant__c | Primary_Parent_Contact__c, Camp_Class__c, Order__c |
| Camp / class | Camp__c | Start_Date__c, Type__c |
| Staff notes | Team_notes__c | Contact__c, Lead__c, Opportunity__c, Order__c |
| Email activity | Task | WhoId / WhatId |
| Contact preferences | Email_Preference__c | Email__c, Phone__c |
| Waiver check-ins | Check_In__c | Account__c (0 records in COS today) |
| Minors | Minor__c | Account__c — NEVER sent to AI |

## Allowlist — fields the AI may see (after pseudonymization)

- Account: Number_of_Bookings__c, of_Parties_Hosted__c, Group_Type__c, Is_DayCare__c
- Contact (adults only): Relationship__c, Unsubscribe__c, Square_Origin__c
- Opportunity: StageName, Amount, Event_Type__c, Booking_Type__c, Party_Package__c, Event_Date_and_Start_Time__c, Estimated_Children__c, Estimated_Adults__c, Summary_of_Add_Ons__c, Pizza_or_Add_on_Preferences__c, Laser_Tag__c, Reason_for_Cancellation__c, Party_Re_booked_using_one_time_transfer__c, Previous_Booking__c (as flag)
- Order: EffectiveDate, Status, Total_Amount_with_Taxes__c, Invoice_Status__c, Laser_Tag_Package__c, Number_of_Kids__c, Number_of_Adults__c, Refund_Amount__c
- Lead: Status, Party_Type__c, Booking_Type__c, Preferred_Date__c, Number_of_Kids__c
- Participant__c: Status__c, Camp_Type__c, Registered_for__c, Lunch_Add_On__c, After_Care_Requested__c
- Camp__c: Type__c, Start_Date__c, Duration__c
- Team_notes__c: Comments__c (HTML stripped + redacted), Team_Member__c, CreatedDate
- Task: Subject, ActivityDate, Status, Type
- Email_Preference__c: Marketing_Email__c, Follow_Up_Reselling__c, Unsubscribe__c

## Denylist — never queried by the AI context builder

- Minor__c (whole object)
- Contact: Birthdate, Child_s_Care_Care__c, all Child_* and Details_About_* fields, Medical_Health_Conditions_Notes__c, Medical_Allergy_Spl_Needs__c, ParticipantLIST__c, MailingAddress
- Opportunity: Special_Guest_s_Name__c (child's name)
- Order: ParticipantList__c
- Participant__c: all name, contact, emergency-contact and address formula fields
- Any Name, Email, Phone value (replaced with tokens: Parent A, Booking 1, etc.)

## Free-text risk

Team_notes__c.Comments__c and Pizza_or_Add_on_Preferences__c may contain allergies, names or phone numbers.
Mitigation: redactor strips HTML, masks emails / phone numbers / 9–10 digit IDs, and flags health keywords (allergy, allergic, medication, epipen, condition) as [HEALTH-REDACTED].

## Encryption note

Classic Encryption (no extra licence) only works on new "Text (Encrypted)" fields; existing Care Card fields would need a new field + data migration. Post-capstone item.
