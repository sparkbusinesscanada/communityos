/**
 * Deterministic stand-in for the LLM. No network, no cost.
 * Applies simple business rules to the same context JSON the real model will receive,
 * and returns output in the exact FamilyInsightPrompt schema. It doubles as the
 * rules-only baseline when evaluating the real model later.
 */
public with sharing class MockLlmClient implements LlmClient {
    @TestVisible
    private static final Integer REBOOK_WINDOW_DAYS = 60;
    @TestVisible
    private static final Integer LAPSED_DAYS = 90;

    public String modelName() {
        return 'mock-rules-v1';
    }

    public String complete(String systemPrompt, String contextJson) {
        Map<String, Object> ctx = (Map<String, Object>) JSON.deserializeUntyped(contextJson);
        Date today = Date.valueOf((String) ctx.get('today'));
        List<Object> bookings = (List<Object>) ctx.get('bookings');
        List<Object> orders = (List<Object>) ctx.get('orders');
        List<Object> camps = (List<Object>) ctx.get('camps');
        List<Object> enquiries = (List<Object>) ctx.get('openEnquiries');

        List<Map<String, Object>> insights = new List<Map<String, Object>>();
        List<Map<String, Object>> tasks = new List<Map<String, Object>>();

        Map<String, Object> lastPastParty;
        Boolean hasFutureBooking = false;
        for (Object o : bookings) {
            Map<String, Object> b = (Map<String, Object>) o;
            if (b.get('eventDate') == null) {
                continue;
            }
            Date d = Date.valueOf((String) b.get('eventDate'));
            if (d >= today) {
                hasFutureBooking = true;
            } else if (lastPastParty == null) {
                lastPastParty = b;
            }
        }

        if (lastPastParty != null && !hasFutureBooking) {
            Date partyDate = Date.valueOf((String) lastPastParty.get('eventDate'));
            Date anniversary = Date.newInstance(today.year(), partyDate.month(), partyDate.day());
            if (anniversary < today) {
                anniversary = anniversary.addYears(1);
            }
            Integer daysAway = today.daysBetween(anniversary);
            if (daysAway <= REBOOK_WINDOW_DAYS) {
                String token = (String) lastPastParty.get('token');
                insights.add(new Map<String, Object>{
                    'title' => 'Rebooking window open',
                    'detail' => token + ' party was ' + String.valueOf(partyDate) + '; the anniversary is in ' + daysAway + ' days and nothing is booked yet.'
                });
                tasks.add(new Map<String, Object>{
                    'subject' => 'Call about rebooking this year\'s party',
                    'dueInDays' => 2,
                    'reason' => token + ' party was ' + String.valueOf(partyDate) + '; anniversary on ' + String.valueOf(anniversary) + '.',
                    'relatedToken' => token
                });
            }
        }

        Date lastActivity = latestDate(bookings, 'eventDate', today);
        Date lastOrder = latestDate(orders, 'date', today);
        if (lastOrder != null && (lastActivity == null || lastOrder > lastActivity)) {
            lastActivity = lastOrder;
        }
        if (lastActivity != null && lastActivity.daysBetween(today) > LAPSED_DAYS && !hasFutureBooking) {
            insights.add(new Map<String, Object>{
                'title' => 'Quiet household',
                'detail' => 'No visit, order or party since ' + String.valueOf(lastActivity) + ' (' + lastActivity.daysBetween(today) + ' days).'
            });
        }

        if (!camps.isEmpty()) {
            insights.add(new Map<String, Object>{
                'title' => 'Camp family',
                'detail' => camps.size() + ' camp or class registration(s) on file; a fit for upcoming camp announcements.'
            });
        }

        if (!enquiries.isEmpty()) {
            Map<String, Object> e = (Map<String, Object>) enquiries[0];
            insights.add(new Map<String, Object>{
                'title' => 'Open enquiry',
                'detail' => 'Unconverted ' + (e.get('partyType') == null ? 'party' : e.get('partyType')) +
                    ' enquiry received ' + e.get('received') + '.'
            });
            if (tasks.size() < 3) {
                tasks.add(new Map<String, Object>{
                    'subject' => 'Follow up on open party enquiry',
                    'dueInDays' => 1,
                    'reason' => 'Web enquiry from ' + e.get('received') + ' is still open.',
                    'relatedToken' => 'Household'
                });
            }
        }

        Map<String, Object> household = (Map<String, Object>) ctx.get('household');
        String summary = 'Customer since ' + household.get('customerSince') + ' with ' +
            bookings.size() + ' booking(s), ' + orders.size() + ' order(s) and ' + camps.size() + ' camp registration(s) on file.';
        if (lastPastParty != null) {
            summary += ' Last party: ' + lastPastParty.get('eventDate') +
                (lastPastParty.get('package') == null ? '' : ' (' + lastPastParty.get('package') + ')') + '.';
        }
        if (bookings.isEmpty() && orders.isEmpty() && camps.isEmpty()) {
            summary += ' History is thin, so no strong suggestions yet.';
        }

        return JSON.serialize(new Map<String, Object>{
            'summary' => summary,
            'insights' => insights,
            'suggestedTasks' => tasks
        });
    }

    private static Date latestDate(List<Object> rows, String key, Date notAfter) {
        Date latest;
        for (Object o : rows) {
            Object v = ((Map<String, Object>) o).get(key);
            if (v == null) {
                continue;
            }
            Date d = Date.valueOf((String) v);
            if (d <= notAfter && (latest == null || d > latest)) {
                latest = d;
            }
        }
        return latest;
    }
}
