/**
 * Masks personal and health information in free text before it can leave Salesforce.
 * Order matters: HTML -> emails -> phones -> long digit runs (IDs, care cards) -> known names -> health sentences.
 */
public with sharing class Redactor {
    public static final String HEALTH_MASK = '[HEALTH-REDACTED]';

    private static final String EMAIL_REGEX = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}';
    private static final String PHONE_REGEX = '(?<!\\d)(\\+?1[\\s.-]?)?\\(?\\d{3}\\)?[\\s.-]?\\d{3}[\\s.-]?\\d{4}(?!\\d)';
    private static final String LONG_DIGITS_REGEX = '\\d{7,}';
    private static final Pattern HEALTH_PATTERN = Pattern.compile(
        '(?is).*(allerg|anaphyla|epi-?pen|inhaler|asthma|diabet|insulin|seizure|epilep|autis|adhd|diagnos|' +
        'medical|medicat|medicine|condition|surgery|hospital|celiac|lactose|peanut|\\bnuts?\\b|disabilit|special needs|therapy).*'
    );

    public static String redact(String input) {
        return redact(input, new Set<String>());
    }

    public static String redact(String input, Set<String> knownNames) {
        if (String.isBlank(input)) {
            return input;
        }
        String s = input.stripHtmlTags();
        s = s.replaceAll(EMAIL_REGEX, '[EMAIL]');
        s = s.replaceAll(LONG_DIGITS_REGEX.replace('7,', '11,'), '[ID]');
        s = s.replaceAll(PHONE_REGEX, '[PHONE]');
        s = s.replaceAll(LONG_DIGITS_REGEX, '[ID]');
        s = maskNames(s, knownNames);
        s = maskHealthSentences(s);
        return s.trim();
    }

    private static String maskNames(String s, Set<String> knownNames) {
        if (knownNames == null) {
            return s;
        }
        for (String name : knownNames) {
            if (String.isBlank(name) || name.trim().length() < 2) {
                continue;
            }
            s = s.replaceAll('(?i)\\b' + Pattern.quote(name.trim()) + '\\b', '[NAME]');
        }
        return s;
    }

    private static String maskHealthSentences(String s) {
        List<String> out = new List<String>();
        for (String sentence : s.split('(?<=[.!?\\n])')) {
            if (HEALTH_PATTERN.matcher(sentence).matches()) {
                out.add(' ' + HEALTH_MASK + ' ');
            } else {
                out.add(sentence);
            }
        }
        return String.join(out, '').replaceAll('\\s{2,}', ' ');
    }
}
