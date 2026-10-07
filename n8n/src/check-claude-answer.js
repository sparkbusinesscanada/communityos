// n8n Code node "Check Claude's answer" (deterministic guardrail).
// Accepts the advice only if it is valid JSON, every action cites known facts,
// and every number it uses appears in the facts or rule results. Otherwise the email
// goes out with the exact numbers only.
const base = $('Weekly rules and facts').first().json;
const cfg = base.check || { textFields: ['headline', 'read'], optionalFields: ['watch'], maxActions: 3, promptVersion: 'v1' };
const HARD = ['headline', 'read'];
const res = $input.first().json;
const out = { ok: false, reason: null, advice: null, model: null, raw: null, inputTokens: 0, outputTokens: 0, costUsd: 0, dropped: [] };

const factIds = new Set(base.facts.map((f) => f.id));
const numbersIn = (s) => (String(s)
  .replace(/\b[FR]\d+\b/g, ' ')      // fact and rule IDs are not numbers
  .replace(/(\d),(\d{3})/g, '$1$2')  // 1,846.96 -> 1846.96
  .match(/\d+(?:\.\d+)?/g) || []).map(Number);
const allowed = new Set(numbersIn(JSON.stringify(base.context)));
const numbersOk = (s) => numbersIn(s).every((x) => allowed.has(x) || x <= 3);
const contactDetails = /@|\b\d{3}[\s.-]?\d{3}[\s.-]?\d{4}\b/;
const clean = (s) => numbersOk(s) && !contactDetails.test(String(s));

try {
  if (res.error) {
    throw new Error('Claude call failed: ' + String(res.error.message || JSON.stringify(res.error)).slice(0, 200));
  }
  const usage = res.usage || {};
  out.inputTokens = usage.input_tokens || 0;
  out.outputTokens = usage.output_tokens || 0;
  // claude-sonnet-5 list price: $2 per million input tokens, $10 per million output tokens
  out.costUsd = Math.round(((out.inputTokens * 2 + out.outputTokens * 10) / 1e6) * 10000) / 10000;
  out.model = res.model || null;
  if (res.stop_reason === 'max_tokens') throw new Error('The answer was cut off');
  const text = (res.content || []).filter((c) => c.type === 'text').map((c) => c.text).join('');
  out.raw = text;
  const a = JSON.parse(text);

  if (!a.headline || !a.read) throw new Error('The answer had no headline or summary');
  if (!clean(a.headline) || !clean(a.read)) throw new Error('The summary used a number that is not in the facts');
  for (const k of [...cfg.textFields, ...cfg.optionalFields].filter((k) => !HARD.includes(k))) {
    if (a[k] && !clean(a[k])) { out.dropped.push(`${k}: number not in the facts`); a[k] = ''; }
  }

  const actions = [];
  for (const x of a.actions || []) {
    const cites = (x.cites || []).filter((c) => factIds.has(c));
    if (!cites.length) { out.dropped.push(`"${x.title}": cites no known fact`); continue; }
    if (!clean(x.title + ' ' + x.why)) { out.dropped.push(`"${x.title}": number not in the facts`); continue; }
    actions.push({ title: x.title, why: x.why, cites, owner: x.owner, when: x.when });
    if (actions.length === cfg.maxActions) break;
  }
  if ((a.actions || []).length > cfg.maxActions) out.dropped.push(`only the first ${cfg.maxActions} actions are kept`);
  a.actions = actions;
  out.advice = a;
  out.ok = true;
  out.reason = out.dropped.length ? 'Partly rejected: ' + out.dropped.join('; ') : null;
} catch (e) {
  out.ok = false;
  out.reason = e.message;
}
// Record for AI_Call_Log__c in Salesforce, so the call counts toward the usage banner and budget
const status = !out.ok ? 'Failed' : out.dropped.length ? 'Partly rejected' : 'Success';
out.logRecord = {
  Model__c: out.model || base.claudeRequest.model,
  Status__c: status,
  Prompt_Version__c: cfg.promptVersion + '/' + base.rulesVersion,
  Input_Tokens__c: out.inputTokens,
  Output_Tokens__c: out.outputTokens,
  Est_Cost_USD__c: out.costUsd,
  Schema_Enforced__c: true,
  Tasks_Suggested__c: out.advice ? out.advice.actions.length : 0,
  Fields_Sent__c: 'Weekly facts and rule results only (counts and rates; no names, no contact details, no children)',
  Context_Json__c: JSON.stringify(base.context).slice(0, 131000),
  Response_Json__c: String(out.raw || '').slice(0, 131000),
  Error__c: out.reason ? String(out.reason).slice(0, 32000) : null
};
return [{ json: out }];
