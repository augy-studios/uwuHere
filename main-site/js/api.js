// Calls to /api, in one shape whatever happens:
//
//   { ok: true,  status, data }
//   { ok: false, status, error, reason, data, offline }
//
// A network failure is not thrown. Offline is an ordinary answer in this
// app, and every caller has a sentence ready for it.

const OFFLINE_RESULT = {
  ok: false,
  status: 0,
  error: "You appear to be offline.",
  reason: "offline",
  offline: true,
};

// Sends one request to /api/<path> and turns whatever comes back (or the lack
// of an answer) into the single result shape described above.
export async function api(path, { method = "GET", body, headers = {} } = {}) {
  let contentTypeHeaders;
  if (body) {
    contentTypeHeaders = { "Content-Type": "application/json" };
  } else {
    contentTypeHeaders = {};
  }

  let requestBody;
  if (body) {
    requestBody = JSON.stringify(body);
  } else {
    requestBody = undefined;
  }

  let response;
  try {
    response = await fetch(`/api/${path}`, {
      method,
      cache: "no-store",
      headers: { ...contentTypeHeaders, ...headers },
      body: requestBody,
    });
  } catch {
    return { ...OFFLINE_RESULT };
  }

  let payload = null;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }

  const payloadExists = payload !== null && payload !== undefined;

  if (response.ok && payloadExists && payload.ok) {
    return { ok: true, status: response.status, data: payload.data };
  }

  // The service worker answers 503 with reason "offline" when the network is
  // gone, which is the same thing as the fetch above failing.
  if (payloadExists && payload.reason === "offline") {
    return { ...OFFLINE_RESULT };
  }

  let errorMessage = "Something went wrong. Try again.";
  let reason = "error";
  let data = undefined;
  if (payloadExists) {
    if (payload.error) {
      errorMessage = payload.error;
    }
    if (payload.reason) {
      reason = payload.reason;
    }
    data = payload.data;
  }

  return {
    ok: false,
    status: response.status,
    error: errorMessage,
    reason,
    data,
    offline: false,
  };
}

export function postJson(path, body) {
  return api(path, { method: "POST", body });
}
