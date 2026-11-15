// Tests main-site/api/bug-report.js on made-up requests, with Telegram stood in for: what it
// refuses, the report ID, what's sent to each chat (a rich message, else plain text with the
// pictures replying), that nothing typed is read as Markdown, and the limits.
//
//   node scripts/bug-report-test.mjs
//
// The site's form itself is driven in a browser by flutter/e2e/tests/site.spec.js.
import assert from "node:assert/strict";

process.env.BUG_REPORT_BOT_TOKEN = "123:TEST";
process.env.BUG_REPORT_CHAT_ID = "424242, -1001234567890/17, @channel, not-a-chat";

const api = await import("../main-site/api/bug-report.js");
const handler = api.default;

let sent = [];
let telegram = () => ({ ok: true, result: { message_id: 7 } });
globalThis.fetch = async (url, init = {}) => {
  const method = String(url).split("/").pop();
  const body = init.body instanceof FormData ? Object.fromEntries([...init.body.entries()].map(([k, v]) => [k, typeof v === "string" ? v : `<file ${v.size}>`])) : JSON.parse(init.body || "{}");
  sent.push({ method, body });
  const answer = telegram(method, body);
  return new Response(JSON.stringify(answer), { status: answer.ok ? 200 : 400 });
};

function call(body, headers = {}) {
  return new Promise((resolve) => {
    const res = {
      statusCode: 0,
      headers: {},
      setHeader(k, v) { this.headers[k] = v; },
      status(c) { this.statusCode = c; return this; },
      json(d) { resolve({ status: this.statusCode, body: d }); },
    };
    handler({ method: "POST", headers: { host: "here.uwuapps.org", "x-real-ip": `10.0.0.${Math.floor(Math.random() * 250)}`, ...headers }, body }, res);
  });
}

const png = `data:image/png;base64,${Buffer.from("not really a png but bytes").toString("base64")}`;
let failures = 0;
async function check(name, fn) {
  sent = [];
  telegram = () => ({ ok: true, result: { message_id: 7 } });
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (e) {
    failures++;
    console.log(`FAIL ${name}\n     ${e.message}`);
  }
}

await check("chats: IDs, topics and @names, in order, anything else left out", () => {
  assert.deepEqual(api.chats(), [{ chat_id: "424242" }, { chat_id: "-1001234567890", message_thread_id: 17 }, { chat_id: "@channel" }]);
});

await check("report IDs: the day in Singapore and four readable letters", () => {
  const id = api.reportId(new Date("2026-11-14T17:30:00Z"), (n) => Buffer.alloc(n, 0));
  assert.equal(id, "20261115-2222");
  assert.match(api.reportId(), /^\d{8}-[2-9A-HJKMNP-Z]{4}$/);
});

await check("typed text is escaped: nothing is read as Markdown or HTML", () => {
  const md = api.richMarkdown({ id: "X", text: "# not a heading\n- not a list *bold* <b>x</b> [a](b)", platform: "web" });
  assert.match(md, /\\# not a heading/);
  assert.match(md, /\\- not a list \\\*bold\\\* \\<b\\>x\\<\/b\\> \\\[a\\\]\\\(b\\\)/);
});

await check("refuses: nothing typed, too long, bad pictures, another site's page", async () => {
  assert.equal((await call({ text: "hi" })).status, 400);
  assert.equal((await call({ text: "x".repeat(2001) })).status, 400);
  assert.equal((await call({ text: "A real report.", images: ["data:text/plain;base64,aGk="] })).status, 400);
  assert.equal((await call({ text: "A real report.", images: [png, png, png, png] })).status, 400);
  assert.equal((await call({ text: "A real report." }, { origin: "https://evil.example" })).status, 403);
  assert.equal(sent.length, 0);
});

await check("sends a rich message to every chat, with its pictures, and answers its ID", async () => {
  const r = await call({ text: "The list jumps.", contact: "@sam", platform: "android", version: "2.0.0", device: "Android 16", page: "Host page", images: [png], full: [0] });
  assert.equal(r.status, 200);
  assert.match(r.body.id, /^\d{8}-[2-9A-HJKMNP-Z]{4}$/);
  const rich = sent.filter((s) => s.method === "sendRichMessage");
  assert.equal(rich.length, 3);
  const msg = JSON.parse(rich[0].body.rich_message);
  assert.ok(msg.markdown.startsWith(`# Bug report ${r.body.id}\n`));
  assert.match(msg.markdown, /\| App \| Android app 2\.0\.0 \|/);
  assert.match(msg.markdown, /\*uwuHere\*/);
  assert.equal(msg.media.length, 1);
  // The whole page also as a file, replying to the report.
  assert.equal(sent.filter((s) => s.method === "sendDocument").length, 3);
});

await check("a chat that won't take a rich message gets plain text, the pictures replying to it", async () => {
  telegram = (method) => (method === "sendRichMessage" ? { ok: false, description: "Bad Request: method not found" } : { ok: true, result: { message_id: 9 } });
  const r = await call({ text: "Plain text please.", images: [png] });
  assert.equal(r.status, 200);
  const plain = sent.filter((s) => s.method === "sendMessage");
  assert.equal(plain.length, 3);
  assert.match(plain[0].body.text, /Bug report \d{8}-\w{4}, uwuHere/);
  assert.equal(sent.filter((s) => s.method === "sendPhoto").length, 3);
});

await check("the bot's hidden field: told it went, nothing sent", async () => {
  const r = await call({ text: "Buy my pills.", website: "spam.example" });
  assert.equal(r.status, 200);
  assert.equal(sent.length, 0);
});

await check("not set up: 503, so the form offers email", async () => {
  const token = process.env.BUG_REPORT_BOT_TOKEN;
  delete process.env.BUG_REPORT_BOT_TOKEN;
  assert.equal((await call({ text: "Hello there." })).status, 503);
  process.env.BUG_REPORT_BOT_TOKEN = token;
});

await check("two a minute from one address, then 429", async () => {
  const ip = { "x-real-ip": "192.0.2.9" };
  assert.equal((await call({ text: "One report." }, ip)).status, 200);
  assert.equal((await call({ text: "Two reports." }, ip)).status, 200);
  assert.equal((await call({ text: "Three reports." }, ip)).status, 429);
});

console.log(failures ? `\n${failures} failed` : "\nAll passed");
process.exit(failures ? 1 : 0);
