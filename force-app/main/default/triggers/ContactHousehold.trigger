trigger ContactHousehold on Contact (after insert, after update) {
    ContactHouseholdService.link(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
