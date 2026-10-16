/* A tiny Supabase REST client.

   Hand written rather than pulling in @supabase/supabase-js, because this
   project has no build step and needs a handful of PostgREST calls. Every
   call uses the service role key, which never reaches the browser.

   Values that end up in a filter (codes, uuids, hashes) are validated by the
   callers before they get here, so nothing user-typed is spliced into a
   PostgREST filter expression. */

const URL_BASE = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";

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
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);

  const headers = {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
  };
  if (prefer) headers.Prefer = prefer;

  try {
    const response = await fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    const text = await response.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = null;
    }

    return { ok: response.ok, status: response.status, data };
  } catch (cause) {
    console.error("[uwuhere] supabase unreachable:", cause?.message ?? cause);
    return { ok: false, status: 0, data: null };
  }
}
