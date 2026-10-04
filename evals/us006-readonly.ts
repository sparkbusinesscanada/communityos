import { execFileSync } from "node:child_process";

const INTEGRATION_ALIAS = process.env.SF_INTEGRATION_ALIAS ?? "commos-int";
const API = "v66.0";

const GRAPH_OBJECTS = [
  "Account",
  "Contact",
  "Minor__c",
  "Opportunity",
  "Participant__c",
  "Camp__c",
  "Check_In__c",
  "Contract",
  "Visit__c",
  "Enquiry__c",
  "Waiver__c",
  "Desk_Question__c",
  "Merge_Candidate__c",
];

const HIDDEN_FIELDS: Array<[string, string]> = [
  ["Minor__c", "Medical_Information__c"],
  ["Minor__c", "BC_Care_Card__c"],
  ["Minor__c", "Unauthorized_Person__c"],
  ["Contact", "Details_About_Allergies__c"],
  ["Contact", "Medical_Health_Conditions_Notes__c"],
];

type Session = { instanceUrl: string; accessToken: string; username: string };
type Check = { object: string; check: string; pass: boolean; detail: string };

function session(alias: string): Session {
  const out = execFileSync("sf", ["org", "display", "--target-org", alias, "--json"], { encoding: "utf8" });
  const r = JSON.parse(out).result;
  return { instanceUrl: r.instanceUrl, accessToken: r.accessToken, username: r.username };
}

async function call(s: Session, method: string, path: string, body?: unknown) {
  const res = await fetch(`${s.instanceUrl}/services/data/${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${s.accessToken}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { status: res.status, json };
}

function codes(json: any): string[] {
  const out: string[] = [];
  const walk = (v: any) => {
    if (!v) return;
    if (Array.isArray(v)) return v.forEach(walk);
    if (typeof v === "object") {
      if (typeof v.errorCode === "string") out.push(v.errorCode);
      if (typeof v.statusCode === "string") out.push(v.statusCode);
      Object.values(v).forEach(walk);
    }
  };
  walk(json);
  return out;
}

function writeDenied(res: { status: number; json: any }, realIndex: number): { pass: boolean; detail: string } {
  if (res.status >= 400) {
    return { pass: true, detail: `HTTP ${res.status} ${codes(res.json).join(",") || ""}`.trim() };
  }
  const rows = Array.isArray(res.json) ? res.json : [];
  const real = rows[realIndex];
  if (!real) return { pass: false, detail: `unexpected response ${JSON.stringify(res.json).slice(0, 200)}` };
  if (real.success === true) return { pass: false, detail: "WRITE SUCCEEDED" };
  const c = codes(real);
  if (c.includes("ALL_OR_NONE_OPERATION_ROLLED_BACK")) {
    return { pass: false, detail: "permitted (rolled back only because the decoy failed)" };
  }
  return { pass: true, detail: c.join(",") || "denied" };
}

async function main() {
  const s = session(INTEGRATION_ALIAS);
  console.log(`US-006 read-only eval as ${s.username}\n`);
  const results: Check[] = [];

  for (const obj of GRAPH_OBJECTS) {
    const d = await call(s, "GET", `/sobjects/${obj}/describe`);
    if (d.status !== 200) {
      results.push({ object: obj, check: "describe", pass: false, detail: `HTTP ${d.status} ${codes(d.json).join(",")}` });
      continue;
    }
    const desc = d.json;
    results.push({ object: obj, check: "queryable", pass: desc.queryable === true, detail: String(desc.queryable) });
    results.push({ object: obj, check: "describe: not createable", pass: desc.createable === false, detail: String(desc.createable) });
    results.push({ object: obj, check: "describe: not updateable", pass: desc.updateable === false, detail: String(desc.updateable) });
    results.push({ object: obj, check: "describe: not deletable", pass: desc.deletable === false, detail: String(desc.deletable) });
    const writableFields = (desc.fields as any[]).filter((f) => f.createable || f.updateable).map((f) => f.name);
    results.push({
      object: obj,
      check: "describe: no writable fields",
      pass: writableFields.length === 0,
      detail: writableFields.length ? writableFields.slice(0, 5).join(",") : "0",
    });

    const q = await call(s, "GET", `/query?q=${encodeURIComponent(`SELECT Id FROM ${obj} ORDER BY CreatedDate DESC LIMIT 1`)}`);
    results.push({ object: obj, check: "read: SELECT succeeds", pass: q.status === 200, detail: `HTTP ${q.status}` });

    const decoyId = `${desc.keyPrefix}000000000000`;
    const ins = await call(s, "POST", "/composite/sobjects", {
      allOrNone: true,
      records: [{ attributes: { type: obj } }, { attributes: { type: obj }, Id: decoyId }],
    });
    const insR = writeDenied(ins, 0);
    results.push({ object: obj, check: "insert denied", pass: insR.pass, detail: insR.detail });

    const realId: string | undefined = q.json?.records?.[0]?.Id;
    if (!realId) {
      results.push({ object: obj, check: "update/delete denied", pass: true, detail: "no rows yet; covered by describe flags" });
      continue;
    }
    const upd = await call(s, "PATCH", "/composite/sobjects", {
      allOrNone: true,
      records: [{ attributes: { type: obj }, id: realId }, { attributes: { type: obj }, id: decoyId }],
    });
    const updR = writeDenied(upd, 0);
    results.push({ object: obj, check: "update denied", pass: updR.pass, detail: updR.detail });

    const del = await call(s, "DELETE", `/composite/sobjects?allOrNone=true&ids=${realId},${decoyId}`);
    const delR = writeDenied(del, 0);
    results.push({ object: obj, check: "delete denied", pass: delR.pass, detail: delR.detail });
  }

  for (const [obj, field] of HIDDEN_FIELDS) {
    const q = await call(s, "GET", `/query?q=${encodeURIComponent(`SELECT ${field} FROM ${obj} LIMIT 1`)}`);
    results.push({ object: obj, check: `FLS hides ${field}`, pass: q.status >= 400, detail: `HTTP ${q.status} ${codes(q.json).join(",")}` });
  }

  const width = Math.max(...results.map((r) => r.object.length));
  for (const r of results) {
    console.log(`${r.pass ? "PASS" : "FAIL"}  ${r.object.padEnd(width)}  ${r.check.padEnd(34)} ${r.detail}`);
  }
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  process.exit(failed.length === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
