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

function send(res, status, payload) {
  // Nothing here is ever cacheable: every answer is about live state.
  res.setHeader("Cache-Control", "no-store, private");
  res.status(status).json(payload);
}

export function ok(res, data, status = 200) {
  send(res, status, { ok: true, data });
}

/**
 * Wraps a handler with the method check, the configuration check, and the
 * error handling, so each endpoint is only its own logic.
 */
export function endpoint(methods, handler) {
  return async function wrapped(req, res) {
    if (!methods.includes(req.method)) {
      res.setHeader("Allow", methods.join(", "));
      return send(res, 405, { ok: false, error: `Use ${methods.join(" or ")}.`, reason: "method" });
    }

    if (!hasSupabase()) {
      return send(res, 503, {
        ok: false,
        error: "uwuHere is not configured on this deployment yet.",
        reason: "unconfigured",
      });
    }

    try {
      await handler(req, res);
    } catch (cause) {
      if (cause instanceof HttpError) {
        return send(res, cause.status, {
          ok: false,
          error: cause.message,
          reason: cause.reason,
          ...(cause.extra ? { data: cause.extra } : {}),
        });
      }
      console.error("[uwuhere] unhandled:", cause);
      return send(res, 500, { ok: false, error: "Something went wrong. Try again.", reason: "error" });
    }
  };
}

/** A failed database call, as the error a person sees. */
export function dbError(result) {
  console.error("[uwuhere] supabase answered", result.status, JSON.stringify(result.data));
  return new HttpError(503, "The attendance service is unavailable right now. Try again.", "db");
}

export async function readBody(req) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string") return safeParse(req.body);

  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return safeParse(Buffer.concat(chunks).toString("utf8"));
}

function safeParse(text) {
  try {
    const value = JSON.parse(text);
    return value && typeof value === "object" ? value : {};
  } catch {
    return {};
  }
}
