// n8n Code node "Rules and facts" (deterministic, no AI).
// Turns the Salesforce brief into numbered facts (F1..Fn) and fixed rule results (R1..Rn).
// Same input always gives the same output. Change thresholds here and bump RULES_VERSION.
const RULES_VERSION = 'rules-v1';
const b = $input.first().json;

const n = (x) => Number(x || 0);
const money = (x) => '$' + n(x).toFixed(2);
const pct = (value, base) => (base > 0 ? Math.round((value / base) * 100) : null);
const weight = { red: 3, amber: 2, info: 0, green: 0 };

const facts = [];
const rules = [];
const fact = (label, value, compare) => {
  const id = 'F' + (facts.length + 1);
  facts.push({ id, label, value, compare: compare || null });
  return id;
};
const rule = (name, status, factIds, why, impact) => {
  rules.push({ id: 'R' + (rules.length + 1), name, status, facts: factIds, why, score: weight[status] * impact });
};
const day = b.yesterdayWeekday || 'yesterday';

// Today
const partiesToday = (b.partiesToday || []).length;
const kidsToday = (b.partiesToday || []).reduce((s, p) => s + n(p.kids), 0);
const fToday = fact('Parties today', partiesToday, `${kidsToday} kids expected`);

// R1 Drop-in visits vs the same weekday
const fDrop = fact(`Drop-in visits yesterday (${day})`, n(b.dropInsYesterday), `average of the last 4 ${day}s: ${n(b.dropInsSameWeekdayAvg4w)}`);
const dropPct = pct(n(b.dropInsYesterday), n(b.dropInsSameWeekdayAvg4w));
rule('Drop-in traffic vs a normal ' + day,
  dropPct === null ? 'info' : dropPct < 70 ? 'red' : dropPct < 90 ? 'amber' : 'green',
  [fDrop], dropPct === null ? 'No baseline yet' : `${dropPct}% of a normal ${day}`, 2);

// R2 Drop-in spend vs the same weekday
const fSpend = fact(`Drop-in spend yesterday (${day})`, money(b.dropInSpendYesterday), `average of the last 4 ${day}s: ${money(b.dropInSpendSameWeekdayAvg4w)}`);
const spendPct = pct(n(b.dropInSpendYesterday), n(b.dropInSpendSameWeekdayAvg4w));
rule('Drop-in spend vs a normal ' + day,
  spendPct === null ? 'info' : spendPct < 70 ? 'red' : spendPct < 90 ? 'amber' : 'green',
  [fSpend], spendPct === null ? 'No baseline yet' : `${spendPct}% of a normal ${day}`, 2);

// R3 Week vs week
const fWeek = fact('Drop-in visits, last 7 days', n(b.dropInsLast7Days), `previous 7 days: ${n(b.dropInsPrior7Days)}`);
const weekPct = pct(n(b.dropInsLast7Days), n(b.dropInsPrior7Days));
rule('Drop-in visits, week vs week',
  weekPct === null ? 'info' : weekPct < 70 ? 'red' : weekPct < 90 ? 'amber' : 'green',
  [fWeek], weekPct === null ? 'No baseline yet' : `${weekPct}% of the previous week`, 2);

// R4 / R5 Parties not yet confirmed
const fP2 = fact('Parties in the next 2 days not yet confirmed or paid', n(b.partiesNext2DaysNotConfirmed));
rule('Parties about to happen without confirmation', n(b.partiesNext2DaysNotConfirmed) > 0 ? 'red' : 'green',
  [fP2], n(b.partiesNext2DaysNotConfirmed) > 0 ? 'Confirm before the party day' : 'All confirmed', 3);
const fP7 = fact('Parties in the next 7 days not yet confirmed or paid', n(b.partiesNext7DaysNotConfirmed), `of ${n(b.partiesNext7Days)} parties in the next 7 days`);
rule('Parties this week without confirmation', n(b.partiesNext7DaysNotConfirmed) > 0 ? 'amber' : 'green',
  [fP7], n(b.partiesNext7DaysNotConfirmed) > 0 ? 'Chase confirmations this week' : 'All confirmed', 2);

// R6 New party bookings, week vs week
const fBook = fact('New party bookings, last 7 days', n(b.partyBookingsLast7Days), `previous 7 days: ${n(b.partyBookingsPrior7Days)}`);
const bookPct = pct(n(b.partyBookingsLast7Days), n(b.partyBookingsPrior7Days));
const bookStatus = n(b.partyBookingsLast7Days) + n(b.partyBookingsPrior7Days) === 0 ? 'amber'
  : bookPct === null ? 'green' : bookPct < 70 ? 'red' : bookPct < 100 ? 'amber' : 'green';
rule('Party bookings, week vs week', bookStatus, [fBook],
  bookPct === null ? (n(b.partyBookingsLast7Days) > 0 ? 'Bookings up from zero' : 'No new bookings in 14 days') : `${bookPct}% of the previous week`, 3);

// R7 Open enquiries
const fEnq = fact('Open party enquiries not yet booked', n(b.openPartyEnquiries),
  b.oldestOpenEnquiryDays == null ? null : `oldest is ${n(b.oldestOpenEnquiryDays)} days old`);
rule('Enquiries waiting to be booked',
  n(b.openPartyEnquiries) === 0 ? 'green' : n(b.oldestOpenEnquiryDays) > 7 ? 'red' : 'amber',
  [fEnq], n(b.openPartyEnquiries) === 0 ? 'None open' : 'Each open enquiry is a party not yet won', 3);

// R8 Money owed
const fU30 = fact('Unpaid orders older than 30 days', n(b.unpaidOver30Days), `worth ${money(b.unpaidOver30DaysTotal)}`);
const fU8 = fact('Unpaid orders 8 to 30 days old', n(b.unpaid8To30Days));
const fU7 = fact('Unpaid orders up to 7 days old', n(b.unpaidUpTo7Days), `all unpaid: ${n(b.unpaidOrders)} worth ${money(b.unpaidTotal)}`);
rule('Money owed', n(b.unpaidOver30Days) > 0 ? 'red' : n(b.unpaid8To30Days) > 0 ? 'amber' : 'green',
  [fU30, fU8, fU7], n(b.unpaidOver30Days) > 0 ? 'Old unpaid orders: collect or close them' : 'Nothing old outstanding', 2);

// R9 Rebooking list
const fReb = fact('Families whose party anniversary is in the next 30 days with nothing booked', n(b.rebookingCandidatesNext30Days),
  `rebooking reminders due today: ${n(b.rebookingTasksDueToday)}`);
rule('Rebooking opportunity', n(b.rebookingCandidatesNext30Days) > 0 ? 'amber' : 'green',
  [fReb], n(b.rebookingCandidatesNext30Days) > 0 ? 'Past party families to invite back' : 'No anniversaries coming up', 3);

// R10 Overdue tasks
const fTasks = fact('Open tasks due today or overdue', n(b.openTasksDueToday));
rule('Overdue follow-ups', n(b.openTasksDueToday) > 10 ? 'red' : n(b.openTasksDueToday) > 0 ? 'amber' : 'green',
  [fTasks], n(b.openTasksDueToday) > 0 ? 'Follow-ups are piling up' : 'Up to date', 1);

// R11 Square sync health
const syncOk = !b.squareSyncStatus || String(b.squareSyncStatus).startsWith('OK');
const fSync = fact('Square visit sync', syncOk ? 'OK' : 'Failing', b.squareLastSync ? `last run ${b.squareLastSync}` : null);
rule('Square data is current', syncOk ? 'green' : 'red', [fSync], syncOk ? 'Visits are up to date' : 'Visit numbers may be missing', 2);

// R12 AI budget
const budget = b.aiMonthlyBudget == null ? null : n(b.aiMonthlyBudget);
const spent = n(b.aiCostThisMonth);
const fAi = fact('AI spend this month', money(spent), budget == null ? 'no budget set' : `budget ${money(budget)}`);
const budgetPct = budget ? pct(spent, budget) : null;
rule('AI budget', budgetPct === null ? 'info' : budgetPct >= 100 ? 'red' : budgetPct >= 80 ? 'amber' : 'green',
  [fAi], budgetPct === null ? 'No budget set' : `${budgetPct}% of the monthly budget used`, 1);

rules.sort((a, c) => c.score - a.score || Number(a.id.slice(1)) - Number(c.id.slice(1)));

return [{ json: { brief: b, rulesVersion: RULES_VERSION, facts, rules } }];
