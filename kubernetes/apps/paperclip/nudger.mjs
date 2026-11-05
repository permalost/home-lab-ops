// Wakes the agent whose review of an `in_review` issue never started. Paperclip drops the
// handoff wake (upstream #13532, #18315), so this checks state, not events: safe to run often.
// Keep dollar-brace placeholders (template literals) out of this file: Flux substitutes them in the ConfigMap.
import http from "node:http";
import https from "node:https";
import { readFileSync } from "node:fs";

const env = process.env;
const BASE = new URL(env.PAPERCLIP_URL || "http://paperclip:3100");
const HOST = env.PAPERCLIP_HOST || "";
const APPLY = env.APPLY === "1" || env.APPLY === "true";
const GRACE_S = Number(env.GRACE_SECONDS || 120); // let a normal wake land first
const MAX_AGE_S = Number(env.MAX_AGE_HOURS || 24) * 3600; // older stalls need a human
const MAX_WAKES = Number(env.MAX_WAKES || 5);
const BUCKET_S = 600; // at most one wake attempt per issue per 10 minutes
const token = (env.PAPERCLIP_TOKEN || readFileSync(env.PAPERCLIP_TOKEN_FILE, "utf8")).trim();

function api(method, path, body) {
  const lib = BASE.protocol === "https:" ? https : http;
  const headers = { authorization: "Bearer " + token, "content-type": "application/json" };
  if (HOST) headers.host = HOST;
  return new Promise((resolve, reject) => {
    const req = lib.request(
      { hostname: BASE.hostname, port: BASE.port || undefined, path, method, headers, timeout: 20000 },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          if (res.statusCode >= 400) return reject(new Error(method + " " + path + " -> " + res.statusCode + " " + data.slice(0, 200)));
          try { resolve(data ? JSON.parse(data) : null); } catch (e) { reject(e); }
        });
      },
    );
    req.on("timeout", () => req.destroy(new Error("timeout " + method + " " + path)));
    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

const company = env.COMPANY_ID || (await api("GET", "/api/companies"))[0].id;
const agents = new Map((await api("GET", "/api/companies/" + company + "/agents")).map((a) => [a.id, a]));
const issues = (await api("GET", "/api/companies/" + company + "/issues?status=in_review&limit=500"))
  .filter((i) => i.status === "in_review");

const now = Date.now();
let wakes = 0;
let errors = 0;
for (const issue of issues) {
  const rec = { issue: issue.identifier };
  try {
    // Only agent reviews: reviews waiting on a Board question or confirmation are Jon's.
    const part = (issue.reviewAttention?.paths || []).find((p) => p.kind === "execution_participant");
    if (!part) { rec.skip = "no_agent_review_pending"; continue; }
    const agentId = part.ref;
    const agent = agents.get(agentId);
    rec.agent = agent ? agent.name : agentId;
    const ageS = (now - Date.parse(part.since)) / 1000;
    if (!agent || agent.status === "paused" || agent.status === "terminated") { rec.skip = "agent_unavailable"; continue; }
    if (ageS < GRACE_S) { rec.skip = "too_new"; continue; }
    if (ageS > MAX_AGE_S) { rec.skip = "too_old"; continue; }
    if (issue.activeRun || issue.executionRunId) { rec.skip = "running"; continue; }
    const runs = await api("GET", "/api/issues/" + issue.id + "/runs");
    if (runs.some((r) => r.agentId === agentId && Date.parse(r.createdAt) >= Date.parse(part.since) - 5000)) {
      rec.skip = "ran_since"; continue;
    }
    rec.age_min = Math.round(ageS / 60);
    if (!APPLY) { rec.would_wake = true; continue; }
    if (wakes >= MAX_WAKES) { rec.skip = "cap"; continue; }
    const key = "nudge:" + issue.id + ":" + part.since + ":" + Math.floor(now / 1000 / BUCKET_S);
    const res = await api("POST", "/api/agents/" + agentId + "/wakeup", {
      reason: "nudger: review not started after " + rec.age_min + " min",
      payload: { issueId: issue.id },
      idempotencyKey: key,
    });
    wakes += 1;
    rec.woke = true;
    rec.result = (res && (res.status || res.id)) || null;
  } catch (e) {
    errors += 1;
    rec.error = String(e.message || e);
  } finally {
    console.log(JSON.stringify(rec));
  }
}
console.log(JSON.stringify({ summary: true, apply: APPLY, in_review: issues.length, woke: wakes, errors }));
if (errors) process.exitCode = 1;
