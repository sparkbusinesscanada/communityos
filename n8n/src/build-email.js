// n8n Code node "Build email" for the daily brief: rules triggered and exact numbers. No AI (the AI review is weekly).
const base = $('Rules and facts').first().json;
const b = base.brief;
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const colour = { red: '#b42318', amber: '#b54708', green: '#067647', info: '#475467' };
const chip = (s) => `<span style="display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;color:#fff;background:${colour[s] || '#475467'}">${esc(s.toUpperCase())}</span>`;
const reds = base.rules.filter((r) => r.status === 'red').length;
const ambers = base.rules.filter((r) => r.status === 'amber').length;

const adviceHtml = '<p style="color:#475467;font-size:13px">Exact numbers and fixed rules only. The AI business review arrives every Monday.</p>';

const ruleRows = base.rules.filter((r) => r.status !== 'green').map((r) =>
  `<tr><td>${chip(r.status)}</td><td>${esc(r.name)}</td><td>${esc(r.why)}</td><td style="color:#475467">${esc(r.facts.join(', '))}</td></tr>`).join('');
const greens = base.rules.filter((r) => r.status === 'green').map((r) => esc(r.name)).join('; ');
const factRows = base.facts.map((f) =>
  `<tr><td style="color:#475467">${esc(f.id)}</td><td>${esc(f.label)}</td><td><b>${esc(f.value)}</b></td><td style="color:#475467">${esc(f.compare || '')}</td></tr>`).join('');
const parties = (b.partiesToday || []).map((p) =>
  `<tr><td>${esc(p.timeLabel)}</td><td>${esc(p.booking)}</td><td>${esc(p.room)}</td><td>${esc(p.packageName)}</td><td>${p.kids ?? ''}</td><td>${esc(p.stage)}</td></tr>`).join('');
const table = (head, rows) => `<table cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-size:13px;width:100%">${head}${rows}</table>`;

const html = `
<div style="font-family:Arial,Helvetica,sans-serif;max-width:720px;color:#101828">
<h2 style="margin:0">Fun Circle · ${esc(b.forDate)}</h2>
<p style="margin:4px 0;color:#475467">${reds} red, ${ambers} amber · ${(b.partiesToday || []).length} parties today</p>
${adviceHtml}
<h3>Rules triggered (${esc(base.rulesVersion)})</h3>
${ruleRows ? table('<tr style="text-align:left"><th>Status</th><th>Rule</th><th>Why</th><th>Facts</th></tr>', ruleRows) : '<p>Nothing triggered.</p>'}
${greens ? `<p style="color:#067647;font-size:13px">On track: ${greens}</p>` : ''}
<h3>Exact numbers</h3>
${table('<tr style="text-align:left"><th></th><th>Measure</th><th>Value</th><th>Compared with</th></tr>', factRows)}
<h3>Parties today</h3>
${parties ? table('<tr style="text-align:left"><th>Time</th><th>Booking</th><th>Room</th><th>Package</th><th>Kids</th><th>Stage</th></tr>', parties) : '<p>No parties today.</p>'}
<p style="color:#667085;font-size:12px;margin-top:16px">Numbers: Salesforce (read-only). Rules: fixed code in n8n (${esc(base.rulesVersion)}). No AI is used in the daily brief. Nothing is sent to customers.</p>
</div>`;
const subject = `Fun Circle ${b.forDate}: ${reds} red, ${ambers} amber, ${(b.partiesToday || []).length} parties today`;
return [{ json: { subject, html } }];
