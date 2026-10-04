// Read-only smoke: household payload, profile, segments and visit summary for one real household.
Account a = [SELECT Id, Name FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity) ORDER BY LastModifiedDate DESC LIMIT 1];
Family360Controller.Household h = Family360Controller.getHousehold(a.Id);
System.debug('PROFILE ' + JSON.serialize(h.profile));
System.debug('BOOKING OPTIONS ' + h.bookingOptions.size());
EnquiryService.Options o = Family360Controller.getEnquiryOptions();
System.debug('INTENTS ' + o.intents.size() + ' CHANGES ' + o.changes.size() + ' INTERESTS ' + o.interests.size());
System.debug('VISIT ' + JSON.serialize(Family360Controller.getVisitSummary(a.Id)));
