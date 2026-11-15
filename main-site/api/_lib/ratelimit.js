// Limits for the public endpoints anyone can call (api/bug-report.js). Not a function itself:
// Vercel skips files under a folder that starts with an underscore.
//
// rateLimited(key, limit): more than `limit` calls with `key` in a minute, counted in this
// instance's memory. Vercel runs several instances and starts new ones, so it's a nicety that
// stops a burst, not a promise.
//
// With Redis set up (Vercel KV or Upstash: KV_REST_API_URL and KV_REST_API_TOKEN, or
// UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN), redis() runs one command on it, for
// limits that hold across instances. Without it, storeConfigured() is false and callers skip it.

const REDIS_URL = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const REDIS_TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;

export const storeConfigured = () => Boolean(REDIS_URL && REDIS_TOKEN);

export async function redis(...command) {
  const res = await fetch(REDIS_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${REDIS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(command),
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) throw new Error(`Redis replied ${res.status}`);
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  return data.result;
}

const rates = new Map();

export async function rateLimited(key, limit) {
  const now = Date.now();
  let r = rates.get(key);
  if (!r || r.until <= now) {
    r = { count: 0, until: now + 60 * 1000 };
    rates.set(key, r);
  }
  r.count++;
  // Keep the map small: the ones whose minute is over go.
  if (rates.size > 5000) {
    for (const [k, v] of rates) if (v.until <= now) rates.delete(k);
  }
  return r.count > limit;
}

