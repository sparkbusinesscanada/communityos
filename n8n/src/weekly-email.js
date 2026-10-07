// n8n Code node "Build weekly email". Labelled parts: AI review (checked), rules triggered, exact numbers, seasonality.
const base = $('Weekly rules and facts').first().json;
const w = base.weekly;
let ai = null;
try {
  if ($('Check Claude\'s answer').isExecuted) ai = $('Check Claude\'s answer').first().json;
} catch (e) { ai = null; }

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const colour = { red: '#b42318', amber: '#b54708', green: '#067647', info: '#475467' };
const chip = (s) => `<span style="display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;color:#fff;background:${colour[s] || '#475467'}">${esc(s.toUpperCase())}</span>`;
const factById = Object.fromEntries(base.facts.map((f) => [f.id, f]));
const reds = base.rules.filter((r) => r.status === 'red').length;
const ambers = base.rules.filter((r) => r.status === 'amber').length;
const para = (title, text) => (text ? `<p style="margin:10px 0 2px"><b>${esc(title)}</b></p><p style="margin:0">${esc(text)}</p>` : '');

let adviceHtml;
if (ai && ai.ok) {
  const a = ai.advice;
  const actions = a.actions.map((x) => `<li style="margin-bottom:8px"><b>${esc(x.title)}</b><br>${esc(x.why)}<br>
    <span style="color:#475467;font-size:12px">${esc(x.owner)} · ${esc(x.when)} · based on ${x.cites.map((c) => esc(c + ' ' + (factById[c] ? factById[c].label : ''))).join('; ')}</span></li>`).join('');
  adviceHtml = `
  <div style="border:1px solid #d0d5dd;border-radius:8px;padding:12px 16px;margin:12px 0">
    <p style="margin:0 0 4px;font-size:12px;color:#475467;text-transform:uppercase;letter-spacing:.05em">AI business review (Claude, checked against the numbers below)</p>
    <p style="font-size:16px;margin:4px 0"><b>${esc(a.headline)}</b></p>
    ${para('This week', a.read)}
    ${para('Seasons and timing', a.seasonality)}
    ${para('Where to invest effort', a.invest)}
    ${actions ? `<p style="margin:12px 0 4px"><b>Actions</b></p><ol style="margin:0;padding-left:20px">${actions}</ol>` : ''}
    ${para('Watch next week', a.watch)}
    ${ai.reason ? `<p style="margin:8px 0 0;font-size:12px;color:#475467">${esc(ai.reason)}</p>` : ''}
  </div>`;
} else {
  const why = ai ? ai.reason : (base.aiAllowed ? 'Claude was not called' : 'the monthly AI budget is used up');
  adviceHtml = `<p style="border:1px solid #d0d5dd;border-radius:8px;padding:12px 16px;color:#475467">No AI review this week (${esc(why)}). The rules and numbers below are complete.</p>`;
}

const table = (head, rows) => `<table cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-size:13px;width:100%">${head}${rows}</table>`;
const ruleRows = base.rules.filter((r) => r.status !== 'green').map((r) =>
  `<tr><td>${chip(r.status)}</td><td>${esc(r.name)}</td><td>${esc(r.why)}</td><td style="color:#475467">${esc(r.facts.join(', '))}</td></tr>`).join('');
const greens = base.rules.filter((r) => r.status === 'green').map((r) => esc(r.name)).join('; ');
const factRows = base.facts.map((f) =>
  `<tr><td style="color:#475467">${esc(f.id)}</td><td>${esc(f.label)}</td><td><b>${esc(f.value)}</b></td><td style="color:#475467">${esc(f.compare || '')}</td></tr>`).join('');
const monthRows = (w.months || []).slice(-12).map((m) =>
  `<tr><td>${esc(m.month)}</td><td>${m.leads}</td><td>${m.partiesHeld}</td><td>${m.kids}</td><td>${m.avgDaysBookedAhead ?? ''}</td></tr>`).join('');

const html = `
<div style="font-family:Arial,Helvetica,sans-serif;max-width:760px;color:#101828">
<h2 style="margin:0">Fun Circle weekly review · week ending ${esc(w.weekEnding)}</h2>
<p style="margin:4px 0;color:#475467">${reds} red, ${ambers} amber</p>
${adviceHtml}
<h3>Rules triggered (${esc(base.rulesVersion)})</h3>
${ruleRows ? table('<tr style="text-align:left"><th>Status</th><th>Rule</th><th>Why</th><th>Facts</th></tr>', ruleRows) : '<p>Nothing triggered.</p>'}
${greens ? `<p style="color:#067647;font-size:13px">On track: ${greens}</p>` : ''}
<h3>Exact numbers</h3>
${table('<tr style="text-align:left"><th></th><th>Measure</th><th>Value</th><th>Compared with</th></tr>', factRows)}
<h3>Last 12 months</h3>
${table('<tr style="text-align:left"><th>Month</th><th>New leads</th><th>Parties held</th><th>Kids</th><th>Avg days booked ahead</th></tr>', monthRows)}
<p style="color:#667085;font-size:12px;margin-top:16px">Numbers: Salesforce (read-only counts). Rules: fixed code in n8n (${esc(base.rulesVersion)}). Review: Claude, given only the numbered facts (no names or contact details) and checked against them before sending. Nothing is sent to customers.</p>
</div>`;
const headline = ai && ai.ok ? ' · ' + ai.advice.headline : '';
const subject = `Fun Circle weekly review ${w.weekEnding}: ${reds} red, ${ambers} amber${headline}`.slice(0, 200);
return [{ json: { subject, html } }];
