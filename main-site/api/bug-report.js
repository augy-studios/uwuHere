// POST /api/bug-report: Report a bug. The side tray's form (js/bug-report.js) and the apps'
// (flutter/lib/features/bug/bug_report.dart) send what went wrong here, and it reaches Augy as a
// message from a Telegram bot (BUG-REPORT-SETUP.md at the repository root).
//
//   POST { text, contact?, version?, platform?, device?, page?, website?, images?, full? }
//     → 200 { id }
//
// `images` (optional) is up to MAX_IMAGES pictures as JPEG, PNG or WebP data URLs, each at most
// MAX_IMAGE_BYTES (the form makes them JPEGs of about 900 KB at most). `full` (optional) lists
// which of them are whole-page screenshots: as tall (or as wide) as the page, which Telegram
// shrinks as a photo till it can't be read, so each also goes as a file (sendDocument), at its
// full size.
//
// Each report gets an ID, reportId(): the day in Singapore and four letters, "20261103-7K3Q", in
// the message's heading and answered to the form, which shows it, so a report can be talked
// about by it. Nothing's stored: the day keeps them in order, the letters apart.
//
// It goes as a Telegram rich message (Bot API sendRichMessage): a heading, a table of what the
// form added, what was typed under its own heading, and the pictures in the message itself,
// uploaded with it (InputRichMessage `media`, each a tg://photo?id= link in the Markdown). If a
// chat won't take a rich message, it gets the same words as plain text (sendMessage), then the
// pictures as a photo or an album replying to it.
//
// What's sent on is what the person typed (`text`, and `contact` if they gave one), with what
// the form adds and shows them first: the app's version, which app (web, installed web app,
// Android, desktop), the device as their browser or app describes it and the page they were on
// (home, a host page or a check-in page, never an event's code, name or list). Nothing else:
// not their events or anyone's names in them, unless a picture they chose to add shows it.
//
//   BUG_REPORT_BOT_TOKEN  the bot that sends it (BotFather's token)
//   BUG_REPORT_CHAT_ID    the chats it's sent to, one or more, split by commas, spaces or new
//                         lines: a chat ID (a person, who must have started the bot first; a
//                         group or channel the bot's in), a public group or channel's @name, or
//                         <chat ID>/<topic ID> for one topic of a group with topics. README's
//                         "Report a bug" says how to find each
//
// Sent to every chat at once; it counts as sent if one of them took it, and a chat that didn't
// is logged by its place in the list, with Telegram's reason.
//
// Without either it answers 503, and the form offers email instead. A public endpoint, so it's
// kept small: at most MAX_TEXT characters and MAX_BODY bytes besides the pictures, PER_MINUTE a
// minute from one IP in this instance, and with Redis set up (api/_lib/ratelimit.js), PER_HOUR an
// hour from one IP and ALL_PER_HOUR from everyone together. Everything typed is escaped
// (escapeMd), so nothing in it is read as Telegram's Rich Markdown or HTML; the plain text
// fallback has no parse_mode. `website` is a field people never see: filled in, it's a bot,
// told it went and sent nothing.

import { randomBytes } from 'node:crypto';
import { rateLimited, redis, storeConfigured } from './_lib/ratelimit.js';

const APP_NAME = 'uwuHere';
const MAX_TEXT = 2000;
const MAX_CONTACT = 200;
const MAX_BODY = 8 * 1024;
const MAX_IMAGES = 3;
const MAX_IMAGE_BYTES = 1200 * 1024;
const IMAGE_RE = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=]+)$/;
const PER_MINUTE = 2;
const PER_HOUR = 6;
const ALL_PER_HOUR = 60;
const TELEGRAM_MS = 10 * 1000;
const PLATFORMS = { web: 'Web', pwa: 'Web, installed', android: 'Android app', desktop: 'Desktop app' };
// A report ID's letters: no 0 or O, 1, I or L, so one read out or typed back can't be mistaken.
const ID_LETTERS = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const ID_LENGTH = 4;

// "20261103-7K3Q": the day in Singapore it was sent, and ID_LENGTH random letters.
function reportId(now = new Date(), random = (n) => randomBytes(n)) {
  const day = new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10).replace(/-/g, '');
  const letters = [...random(ID_LENGTH)].map((b) => ID_LETTERS[b % ID_LETTERS.length]).join('');
  return `${day}-${letters}`;
}

// The whole-page screenshots among `count` pictures, as their indexes: `full` as sent, each
// once and in range, anything else left out.
function fullShots(full, count) {
  if (!Array.isArray(full)) return [];
  return [...new Set(full.filter((i) => Number.isInteger(i) && i >= 0 && i < count))].sort((a, b) => a - b);
}

// BUG_REPORT_CHAT_ID as [{ chat_id, message_thread_id? }], in order; anything that isn't a chat
// ID, an @name or a chat ID with a topic is left out.
function chats(value = process.env.BUG_REPORT_CHAT_ID) {
  return String(value || '')
    .split(/[\s,]+/)
    .map((t) => {
      const m = t.match(/^(-?\d+)(?:\/(\d+))?$/);
      if (m) return m[2] ? { chat_id: m[1], message_thread_id: Number(m[2]) } : { chat_id: m[1] };
      return /^@[A-Za-z]\w{3,}$/.test(t) ? { chat_id: t } : null;
    })
    .filter(Boolean);
}

const configured = () => Boolean(process.env.BUG_REPORT_BOT_TOKEN && chats().length);

// A string as given, trimmed and cut to `max`, with control characters other than new lines
// and tabs taken out. Anything that isn't a string is "".
function clean(v, max, { lines = false } = {}) {
  if (typeof v !== 'string') return '';
  const s = v.replace(lines ? /[\u0000-\u0008\u000b-\u001f\u007f]/g : /[\u0000-\u001f\u007f]/g, '').trim();
  return s.length > max ? s.slice(0, max) : s;
}

// The pictures sent, as [{ type, bytes }], or null if any isn't one (a bad data URL, too big,
// too many).
function images(list) {
  if (list == null) return [];
  if (!Array.isArray(list) || list.length > MAX_IMAGES) return null;
  const out = [];
  for (const item of list) {
    const m = typeof item === 'string' ? IMAGE_RE.exec(item) : null;
    if (!m) return null;
    const bytes = Buffer.from(m[2], 'base64');
    if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) return null;
    out.push({ type: m[1], bytes });
  }
  return out;
}

const ext = (type) => (type === 'jpeg' ? 'jpg' : type);
const blob = (p) => new Blob([p.bytes], { type: `image/${p.type}` });

// A Bot API method called with a form (files go with it). Its answer's `result`, or throws with
// Telegram's reason: never the token, which is only in the address.
async function telegramForm(method, form, ms) {
  const r = await fetch(`https://api.telegram.org/bot${process.env.BUG_REPORT_BOT_TOKEN}/${method}`, { method: 'POST', body: form, signal: AbortSignal.timeout(ms) });
  if (r.ok) return r.json().then((d) => d?.result ?? null).catch(() => null);
  const reason = await r.json().then((d) => d?.description).catch(() => null);
  throw new Error(`Telegram replied ${r.status}${reason ? `: ${reason}` : ''}`);
}

// A form for one chat, replying to `replyTo` where it's known.
function chatForm(chat, replyTo) {
  const form = new FormData();
  for (const [k, v] of Object.entries(chat)) form.append(k, String(v));
  if (replyTo) form.append('reply_parameters', JSON.stringify({ message_id: replyTo, allow_sending_without_reply: true }));
  return form;
}

// The pictures to one chat, replying to the report (`replyTo`): one as a photo, more as an album.
async function sendImages(chat, pics, replyTo, id) {
  const form = chatForm(chat, replyTo);
  const caption = `${pics.length === 1 ? 'Picture' : `${pics.length} pictures`} for report ${id}`;
  if (pics.length === 1) {
    form.append('photo', blob(pics[0]), `picture.${ext(pics[0].type)}`);
    form.append('caption', caption);
    return telegramForm('sendPhoto', form, TELEGRAM_MS * 2);
  }
  pics.forEach((p, i) => form.append(`p${i}`, blob(p), `picture${i + 1}.${ext(p.type)}`));
  form.append('media', JSON.stringify(pics.map((p, i) => ({ type: 'photo', media: `attach://p${i}`, ...(i === 0 && { caption }) }))));
  return telegramForm('sendMediaGroup', form, TELEGRAM_MS * 2);
}

// A whole-page screenshot (`full`), as a file, so Telegram keeps it at its full size: replying to
// the report where it's known, captioned with the report's ID.
async function sendFile(chat, pic, n, id, replyTo) {
  const form = chatForm(chat, replyTo);
  form.append('document', blob(pic), `report-${id}-page-${n}.${ext(pic.type)}`);
  form.append('caption', `Whole page, picture ${n}, at full size: report ${id}`);
  form.append('disable_content_type_detection', 'true');
  return telegramForm('sendDocument', form, TELEGRAM_MS * 2);
}

// What the form added, as [label, value], in order: the report's ID first.
function details(body) {
  const platform = PLATFORMS[body.platform] || 'Unknown';
  const version = clean(body.version, 60);
  return [
    ...(body.id ? [['Report', body.id]] : []),
    ['App', `${platform}${version ? ` ${version}` : ''}`],
    ['Device', clean(body.device, 200) || 'not given'],
    ['Page', clean(body.page, 100) || 'not given'],
    ['Contact', clean(body.contact, MAX_CONTACT) || 'none given'],
  ];
}

// The message Augy gets as plain text, where a rich message won't go: what the form added,
// then what was typed.
function message(body) {
  const lines = [
    `Bug report${body.id ? ` ${body.id}` : ''}, ${APP_NAME}`,
    '',
    ...details(body).map(([k, v]) => `${k}: ${v}`),
    ...(Array.isArray(body.images) && body.images.length ? [`Pictures: ${body.images.length}, below`] : []),
    '',
    clean(body.text, MAX_TEXT, { lines: true }),
  ];
  return lines.join('\n');
}

// Text for Telegram's Rich Markdown, read as it is: Markdown's and HTML's characters, and the
// ones its own syntax uses (== marked, || spoiler, $ formulas), each behind a backslash, and a
// line that would start a list or a heading made not to.
const MD_SPECIAL = /([\\*_~`|\[\]#>=<!$&^(){}])/g;
function escapeMd(text) {
  return String(text)
    .replace(MD_SPECIAL, '\\$1')
    .replace(/^(\s*)([-+])(?=\s|$)/gm, '$1\\$2')
    .replace(/^(\s*\d+)([.)])/gm, '$1\\$2');
}
// A table cell: escaped, on one line.
const escapeCell = (text) => escapeMd(String(text).replace(/\s*\n\s*/g, ' '));

// The rich message: a heading, the form's details as a table, what was typed under a heading of
// its own (each line kept a line), then each picture as a block of its own, `p0`, `p1`... the
// ids of the files uploaded with it.
function richMarkdown(body, pictures = 0) {
  const typed = clean(body.text, MAX_TEXT, { lines: true }).split('\n').map((l) => escapeMd(l));
  const lines = [
    `# Bug report${body.id ? ` ${escapeMd(body.id)}` : ''}`,
    `*${APP_NAME}*`,
    '',
    '| Detail | Given |',
    '| --- | --- |',
    ...details(body).map(([k, v]) => `| ${k} | ${escapeCell(v)} |`),
    '',
    '## What went wrong',
    '',
    // Two spaces at a line's end keep the next on a line of its own; a blank line stays one.
    ...typed.map((l, i) => (i < typed.length - 1 && l && typed[i + 1] ? `${l}  ` : l)),
  ];
  if (pictures) {
    lines.push('', `## ${pictures === 1 ? 'Picture' : `Pictures (${pictures})`}`);
    for (let i = 0; i < pictures; i++) lines.push('', `![](tg://photo?id=p${i}${pictures > 1 ? ` "Picture ${i + 1} of ${pictures}"` : ''})`);
  }
  return lines.join('\n');
}

// The report as a rich message to one chat, its pictures in it: a form, so the files go with it.
// Its message's ID, for the whole-page files to reply to, or null if Telegram didn't say.
async function sendRich(chat, body, pics) {
  const form = chatForm(chat);
  form.append('rich_message', JSON.stringify({
    markdown: richMarkdown(body, pics.length),
    ...(pics.length && { media: pics.map((p, i) => ({ id: `p${i}`, media: { type: 'photo', media: `attach://p${i}` } })) }),
  }));
  pics.forEach((p, i) => form.append(`p${i}`, blob(p), `picture${i + 1}.${ext(p.type)}`));
  const result = await telegramForm('sendRichMessage', form, TELEGRAM_MS * (pics.length ? 2 : 1));
  return result?.message_id ?? null;
}

// Over the hour's limit, from Redis: one IP's, or everyone's. A Redis that fails lets it through.
async function overHour(ip) {
  if (!storeConfigured()) return false;
  try {
    const hour = Math.floor(Date.now() / 3600000);
    const count = async (key) => {
      const n = await redis('INCR', key);
      if (n === 1) await redis('EXPIRE', key, 3600);
      return n;
    };
    if ((await count(`uwuhere:bug:${hour}:${ip}`)) > PER_HOUR) return true;
    return (await count(`uwuhere:bug:${hour}:all`)) > ALL_PER_HOUR;
  } catch {
    return false; // the limit's a nicety
  }
}

const why = (err) => (err.name === 'TimeoutError' ? 'Telegram took too long' : err.message);

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }
  if (!configured()) return res.status(503).json({ error: "Bug reports can't be sent from the app yet." });

  // Only from the site's own page: a browser sends Origin with a cross-site POST. The apps
  // send none.
  const origin = req.headers.origin;
  if (origin) {
    let host = '';
    try { host = new URL(origin).host; } catch { /* not a URL: refused below */ }
    if (host !== req.headers.host) return res.status(403).json({ error: 'Not from this site.' });
  }

  const body = req.body && typeof req.body === 'object' ? req.body : null;
  if (!body) return res.status(400).json({ error: 'Nothing was sent.' });
  const pics = images(body.images);
  if (!pics) return res.status(400).json({ error: `Pictures must be images, at most ${MAX_IMAGES}, each under ${Math.round(MAX_IMAGE_BYTES / 1024 / 1024 * 10) / 10} MB.` });
  if (JSON.stringify({ ...body, images: undefined }).length > MAX_BODY) return res.status(413).json({ error: "That's too long to send." });
  if (typeof body.text !== 'string' || clean(body.text, MAX_TEXT + 1, { lines: true }).length < 5) return res.status(400).json({ error: 'Please say what went wrong.' });
  if (body.text.trim().length > MAX_TEXT) return res.status(400).json({ error: `Please keep it under ${MAX_TEXT} characters.` });

  const ip = req.headers['x-real-ip'] || String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || 'unknown';
  if (await rateLimited(`bug:${ip}`, PER_MINUTE)) return res.status(429).json({ error: "That's a lot of reports at once. Try again in a minute." });
  // The bot's field: no message, and no sign it was noticed.
  if (body.website) return res.status(200).json({ id: reportId() });
  if (await overHour(ip)) return res.status(429).json({ error: "That's a lot of reports this hour. Try again later." });

  // To every chat at once, as a rich message, or as plain text where that won't go. One that
  // took it is enough; the others are logged.
  const id = reportId();
  const report = { ...body, id };
  const full = fullShots(body.full, pics.length);
  // Each whole-page screenshot as a file too, after the report; the report counts as sent even
  // if they don't go.
  const files = async (chat, i, replyTo) => {
    for (const k of full) {
      await sendFile(chat, pics[k], k + 1, id, replyTo).catch((err) => console.error(`bug-report: chat ${i + 1}: whole page ${k + 1}: ${why(err)}`));
    }
  };
  const text = message(report);
  const results = await Promise.all(chats().map(async (chat, i) => {
    try {
      const sent = await sendRich(chat, report, pics);
      await files(chat, i, sent);
      return true;
    } catch (err) {
      console.error(`bug-report: chat ${i + 1}: rich message: ${why(err)}; sending it as plain text`);
    }
    try {
      const r = await fetch(`https://api.telegram.org/bot${process.env.BUG_REPORT_BOT_TOKEN}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...chat, text, link_preview_options: { is_disabled: true } }),
        signal: AbortSignal.timeout(TELEGRAM_MS),
      });
      if (r.ok) {
        // Then its pictures, replying to it. The report counts as sent even if they don't go.
        const replyTo = await r.json().then((d) => d?.result?.message_id).catch(() => null);
        if (pics.length) {
          await sendImages(chat, pics, replyTo, id).catch((err) => console.error(`bug-report: chat ${i + 1}: pictures: ${why(err)}`));
        }
        await files(chat, i, replyTo);
        return true;
      }
      const reason = await r.json().then((d) => d?.description).catch(() => null);
      console.error(`bug-report: chat ${i + 1}: Telegram replied ${r.status}${reason ? `: ${reason}` : ''}`);
    } catch (err) {
      console.error(`bug-report: chat ${i + 1}: ${why(err)}`);
    }
    return false;
  }));
  if (!results.includes(true)) return res.status(502).json({ error: "Couldn't send it right now. Please try again." });
  return res.status(200).json({ id });
}

// For scripts/bug-report-test.mjs.
export { reportId, fullShots, chats, configured, images, message, escapeMd, richMarkdown };
