/* Request and response plumbing shared by every endpoint.

   Every answer is JSON in one of two shapes:

     { ok: true,  data }
     { ok: false, error, reason }

   `error` is a sentence fit to show a person. `reason` is a short fixed slug
   the client branches on ("too-far", "ended"), so the wording can change
   without breaking anything that reads it. */

import { hasSupabase } from "./supabase.js";

export class HttpError extends Error {
  constructor(status, message, reason = "error", extra = undefined) {
    super(message);
    this.status = status;
    this.reason = reason;
    this.extra = extra;
  }
}

function sendJson(response, status, payload) {
  // Nothing here is ever cacheable: every answer is about live state.
  response.setHeader("Cache-Control", "no-store, private");
  response.status(status).json(payload);
}

export function ok(response, data, status = 200) {
  sendJson(response, status, { ok: true, data });
}

/**
 * Wraps a handler with the method check, the configuration check, and the
 * error handling, so each endpoint is only its own logic.
 */
export function endpoint(methods, handler) {
  return async function wrapped(request, response) {
    if (!methods.includes(request.method)) {
      response.setHeader("Allow", methods.join(", "));
      return sendJson(response, 405, { ok: false, error: `Use ${methods.join(" or ")}.`, reason: "method" });
    }

    if (!hasSupabase()) {
      return sendJson(response, 503, {
        ok: false,
        error: "uwuHere is not configured on this deployment yet.",
        reason: "unconfigured",
      });
    }

    try {
      await handler(request, response);
    } catch (cause) {
      if (cause instanceof HttpError) {
        const payload = {
          ok: false,
          error: cause.message,
          reason: cause.reason,
        };
        if (cause.extra) {
          payload.data = cause.extra;
        }
        return sendJson(response, cause.status, payload);
      }
      console.error("[uwuhere] unhandled:", cause);
      return sendJson(response, 500, { ok: false, error: "Something went wrong. Try again.", reason: "error" });
    }
  };
}

/** A failed database call, as the error a person sees. */
export function databaseError(result) {
  console.error("[uwuhere] supabase answered", result.status, JSON.stringify(result.data));
  return new HttpError(503, "The attendance service is unavailable right now. Try again.", "db");
}

// The request's JSON body as an object: already parsed by Vercel, a string
// to parse, or read from the stream. Anything that is not a JSON object
// becomes {}.
export async function readBody(request) {
  if (request.body && typeof request.body === "object") {
    return request.body;
  }
  if (typeof request.body === "string") {
    return parseJsonObject(request.body);
  }

  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }
  return parseJsonObject(Buffer.concat(chunks).toString("utf8"));
}

function parseJsonObject(text) {
  try {
    const value = JSON.parse(text);
    if (value && typeof value === "object") {
      return value;
    }
    return {};
  } catch {
    return {};
  }
}
