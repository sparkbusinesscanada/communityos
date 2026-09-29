@IsTest
private class RedactorTest {
    @IsTest
    static void masksEmailPhoneAndIds() {
        String out = Redactor.redact('Reach me at jane@example.com or (604) 555-0199. Ref 123456789012.');
        System.assert(out.contains('[EMAIL]'), out);
        System.assert(out.contains('[PHONE]'), out);
        System.assert(out.contains('[ID]'), out);
        System.assert(!out.contains('555'), out);
    }

    @IsTest
    static void masksKnownNamesCaseInsensitive() {
        String out = Redactor.redact('MAYA loved the slide. maya wants laser tag.', new Set<String>{ 'Maya' });
        System.assert(!out.containsIgnoreCase('maya'), out);
        System.assert(out.contains('laser tag'), out);
    }

    @IsTest
    static void masksWholeHealthSentenceKeepsTheRest() {
        String out = Redactor.redact('Wants the jungle room. Has a nut allergy and carries an EpiPen. Pizza: cheese.');
        System.assert(out.contains('jungle room'), out);
        System.assert(out.contains('Pizza: cheese'), out);
        System.assert(out.contains(Redactor.HEALTH_MASK), out);
        System.assert(!out.containsIgnoreCase('epipen'), out);
    }

    @IsTest
    static void stripsHtmlAndHandlesBlank() {
        System.assertEquals('Hello', Redactor.redact('<p><b>Hello</b></p>'));
        System.assertEquals(null, Redactor.redact(null));
    }
}
