/* A tiny Supabase REST client.

   Hand written rather than pulling in @supabase/supabase-js, because this
   project has no build step and needs a handful of PostgREST calls. Every
   call uses the service role key, which never reaches the browser.

   Values that end up in a filter (codes, uuids, hashes) are validated by the
   callers before they get here, so nothing user-typed is spliced into a
   PostgREST filter expression. */

// The project's address without a trailing slash, or "" when it is not set.
function supabaseUrlBase() {
  let url = process.env.SUPABASE_URL;
  if (!url) {
    url = "";
  }
  return url.replace(/\/$/, "");
}

// The service role key, or "" when it is not set.
function supabaseServiceKey() {
  const key = process.env.SUPABASE_SERVICE_KEY;
  if (key) {
    return key;
  }
  return "";
}

const URL_BASE = supabaseUrlBase();
const SERVICE_KEY = supabaseServiceKey();

export function hasSupabase() {
  return Boolean(URL_BASE && SERVICE_KEY);
}

/**
 * One PostgREST request.
 *
 *   path    "uwuhere_events", or "rpc/uwuhere_purge_events"
 *   query   filters and modifiers, e.g. { code: "eq.BCDFGH", select: "*" }
 *   prefer  the Prefer header, e.g. "return=representation"
 *
 * Resolves to { ok, status, data } and never throws: a network failure is
 * status 0, so a caller has one shape to check.
 */
export async function rest(path, { method = "GET", query = {}, body, prefer } = {}) {
  const url = new URL(`${URL_BASE}/rest/v1/${path}`);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }

  const headers = {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
  };
  if (prefer) {
    headers.Prefer = prefer;
  }

  try {
    let requestBody = undefined;
    if (body !== undefined) {
      requestBody = JSON.stringify(body);
    }

    const response = await fetch(url, {
      method,
      headers,
      body: requestBody,
    });

    const text = await response.text();
    let data = null;
    try {
      if (text) {
        data = JSON.parse(text);
      } else {
        data = null;
      }
    } catch {
      data = null;
    }

    return { ok: response.ok, status: response.status, data };
  } catch (cause) {
    let reason = cause;
    if (cause !== null && cause !== undefined && cause.message !== null && cause.message !== undefined) {
      reason = cause.message;
    }
    console.error("[uwuhere] supabase unreachable:", reason);
    return { ok: false, status: 0, data: null };
  }
}

/**
 * The first row a rest() call answered with, or null when there is none:
 * no data at all, an empty list, or a first row that is itself null.
 */
export function firstRow(result) {
  const rows = result.data;
  if (rows === null || rows === undefined) {
    return null;
  }
  const row = rows[0];
  if (row === null || row === undefined) {
    return null;
  }
  return row;
}
