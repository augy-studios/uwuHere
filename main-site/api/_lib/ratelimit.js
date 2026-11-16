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

// The first of two settings that is set and not empty, else the second as it is.
function firstSetValue(first, second) {
  if (first) {
    return first;
  }
  return second;
}

const REDIS_URL = firstSetValue(process.env.KV_REST_API_URL, process.env.UPSTASH_REDIS_REST_URL);
const REDIS_TOKEN = firstSetValue(process.env.KV_REST_API_TOKEN, process.env.UPSTASH_REDIS_REST_TOKEN);

export function storeConfigured() {
  return Boolean(REDIS_URL && REDIS_TOKEN);
}

export async function redis(...command) {
  const response = await fetch(REDIS_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${REDIS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(command),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) {
    throw new Error(`Redis replied ${response.status}`);
  }
  const data = await response.json();
  if (data.error) {
    throw new Error(data.error);
  }
  return data.result;
}

// Each key's calls this minute: { count, until }, `until` being when its minute ends.
const callCountsByKey = new Map();

export async function rateLimited(key, limit) {
  const now = Date.now();
  let entry = callCountsByKey.get(key);
  if (!entry || entry.until <= now) {
    entry = { count: 0, until: now + 60 * 1000 };
    callCountsByKey.set(key, entry);
  }
  entry.count = entry.count + 1;
  // Keep the map small: the ones whose minute is over go.
  if (callCountsByKey.size > 5000) {
    for (const [otherKey, otherEntry] of callCountsByKey) {
      if (otherEntry.until <= now) {
        callCountsByKey.delete(otherKey);
      }
    }
  }
  return entry.count > limit;
}
