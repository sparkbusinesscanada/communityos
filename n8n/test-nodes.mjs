// Local check of the n8n Code nodes with a sample brief and sample Claude replies.
// Run: node n8n/test-nodes.mjs
import fs from 'node:fs';
import assert from 'node:assert';

const src = (f) => fs.readFileSync(new URL('./src/' + f, import.meta.url), 'utf8');
const run = (code, input, nodes) => {
  const $input = { first: () => ({ json: input }) };
  const $ = (name) => ({ isExecuted: name in nodes, first: () => ({ json: nodes[name] }) });
  return new Function('$input', '$', code)($input, $)[0].json;
};

const brief = {
  forDate: '2026-10-07', yesterdayWeekday: 'Tuesday',
  partiesToday: [{ timeLabel: '4:00 PM', booking: 'Sample - Field', room: 'Field', packageName: 'General', kids: 12, stage: 'Call for Final Confirmation' }],
  partiesNext7Days: 8, unpaidOrders: 251, unpaidTotal: 22896.71, rebookingTasksDueToday: 0, openTasksDueToday: 304,
  visitsYesterday: 33, visitsYesterdayLinked: 28, squareSpendYesterday: 1846.96,
  squareSyncStatus: 'OK: 9057 visits saved', squareLastSync: '6 Oct 2:30 AM',
  aiCallsYesterday: 4, aiCostYesterday: 0.06, aiCostThisMonth: 0.31, aiMonthlyBudget: 25,
  dropInsYesterday: 21, dropInSpendYesterday: 640.5, dropInsSameWeekdayAvg4w: 30.5, dropInSpendSameWeekdayAvg4w: 910.25,
  dropInsLast7Days: 180, dropInsPrior7Days: 195, dropInSpendLast7Days: 5400, dropInSpendPrior7Days: 5650,
  partiesNext2DaysNotConfirmed: 1, partiesNext7DaysNotConfirmed: 3, partyBookingsLast7Days: 5, partyBookingsPrior7Days: 9,
  openPartyEnquiries: 12, oldestOpenEnquiryDays: 21, rebookingCandidatesNext30Days: 14,
  unpaidUpTo7Days: 6, unpaid8To30Days: 11, unpaidOver30Days: 234, unpaidOver30DaysTotal: 19000.12
};

// Daily: deterministic only
const rf = run(src('rules-and-facts.js'), brief, {});
assert.equal(rf.rules[0].status, 'red');
const daily = run(src('build-email.js'), {}, { 'Rules and facts': rf });
assert.ok(daily.html.includes('Exact numbers') && !daily.html.includes('AI business review (Claude'));
console.log('daily:', daily.subject);

// Weekly: real counts from the COS sandbox
const weekly = JSON.parse(fs.readFileSync(new URL('../.local/weekly-cos.json', import.meta.url), 'utf8'));
weekly.bookingChangesLast90Days = [{ name: 'Room changed', count: 40 }, { name: 'Adult count changed', count: 38 }, { name: 'Package changed', count: 30 }];
weekly.dateChangeReasonsLast90Days = [{ name: "Customer's One-Time Transfer", count: 12 }, { name: 'Fun Circle Adjustment', count: 9 }];
weekly.cancellationReasonsLast90Days = [{ name: 'Personal Reason', count: 6 }, { name: 'Fun Circle Adjustment', count: 2 }];
const wr = run(src('weekly-rules-and-facts.js'), weekly, {});
assert.ok(wr.aiAllowed);
const ctx = JSON.stringify(wr.context);
assert.ok(!/@|\b\d{10}\b/.test(ctx), 'no contact details reach Claude');
console.log('weekly facts', wr.facts.length);
for (const f of wr.facts) console.log(' ', f.id, f.label, '=', f.value, f.compare ? '| ' + f.compare : '');
console.log('rules', wr.rules.map((r) => `${r.id}:${r.status}:${r.score}`).join(' '));
console.log('request size (chars):', JSON.stringify(wr.claudeRequest).length);

const reply = (obj) => ({ model: 'claude-sonnet-5', stop_reason: 'end_turn', usage: { input_tokens: 3800, output_tokens: 900 },
  content: [{ type: 'text', text: JSON.stringify(obj) }] });
const id = (re) => wr.facts.find((f) => re.test(f.label)).id;
const good = {
  headline: 'Leads and confirmed bookings are well below last year, and the next 4 weeks are booking slowly.',
  read: 'New leads in the last 28 days were 53 against 93 last year, and 29 enquiries are confirmed against 68. Lead to booking conversion improved to 49.1%, so the gap is volume, not follow-up.',
  seasonality: 'November and January are usually strong months, and families are already booking them.',
  invest: 'Most leads come from the web form, so effort on web visibility before the busy months should pay off most.',
  watch: 'Whether booking pace recovers next week.',
  actions: [
    { title: 'Push web promotion for November parties', why: 'Leads are at 53 against 93 last year.', cites: [id(/New leads, last 28/)], owner: 'Marketing', when: 'This week' },
    { title: 'Call open enquiries', why: '15 enquiries are open, the oldest 183 days old.', cites: [id(/Open party enquiries/)], owner: 'Front desk', when: 'This week' },
    { title: 'Invite back anniversary families', why: '44 families have an anniversary coming.', cites: [id(/anniversary/)], owner: 'Party coordinator', when: 'This month' },
    { title: 'Cut venue-caused changes', why: 'Venue adjustments drive 11 changes.', cites: [id(/venue adjustments/)], owner: 'Owner', when: 'This month' },
    { title: 'Extra', why: 'Fifth action', cites: ['F1'], owner: 'Owner', when: 'This week' }
  ]
};
const ok = run(src('check-claude-answer.js'), reply(good), { 'Weekly rules and facts': wr });
assert.ok(ok.ok, ok.reason);
assert.equal(ok.advice.actions.length, 4);
console.log('good:', ok.logRecord.Status__c, '|', ok.reason, '| $' + ok.costUsd, ok.logRecord.Prompt_Version__c);
const bad = run(src('check-claude-answer.js'), reply({ ...good, read: 'Revenue fell 413% this month.' }), { 'Weekly rules and facts': wr });
assert.equal(bad.ok, false);
const soft = run(src('check-claude-answer.js'), reply({ ...good, invest: 'Spend $5,555 more on ads.' }), { 'Weekly rules and facts': wr });
assert.ok(soft.ok && soft.advice.invest === '');
console.log('invented number in invest:', soft.reason);
const email = run(src('weekly-email.js'), {}, { 'Weekly rules and facts': wr, "Check Claude's answer": ok });
fs.writeFileSync(new URL('../.local/sample-weekly-email.html', import.meta.url), email.html);
const noAi = run(src('weekly-email.js'), {}, { 'Weekly rules and facts': { ...wr, aiAllowed: false } });
assert.ok(noAi.html.includes('budget is used up'));
console.log('weekly subject:', email.subject);
console.log('ALL CHECKS PASSED');
