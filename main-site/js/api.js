// Calls to /api, in one shape whatever happens:
//
//   { ok: true,  status, data }
//   { ok: false, status, error, reason, data, offline }
//
// A network failure is not thrown. Offline is an ordinary answer in this
// app, and every caller has a sentence ready for it.

const OFFLINE = {
  ok: false,
  status: 0,
  error: "You appear to be offline.",
  reason: "offline",
  offline: true,
};

export async function api(path, { method = "GET", body, headers = {} } = {}) {
  let response;
  try {
    response = await fetch(`/api/${path}`, {
      method,
      cache: "no-store",
      headers: { ...(body ? { "Content-Type": "application/json" } : {}), ...headers },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    return { ...OFFLINE };
  }

  let payload = null;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }

  if (response.ok && payload?.ok) return { ok: true, status: response.status, data: payload.data };

  // The service worker answers 503 with reason "offline" when the network is
  // gone, which is the same thing as the fetch above failing.
  if (payload?.reason === "offline") return { ...OFFLINE };

  return {
    ok: false,
    status: response.status,
    error: payload?.error || "Something went wrong. Try again.",
    reason: payload?.reason || "error",
    data: payload?.data,
    offline: false,
  };
}

export const postJson = (path, body) => api(path, { method: "POST", body });
