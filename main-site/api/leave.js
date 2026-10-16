/* POST /api/leave   "I'm leaving early"

   Body: { code, deviceId }

   Takes the raw device id, which only the attendee's browser has. The host
   only ever sees its hash, so a host cannot mark somebody as gone.

   Once only: the update matches rows that have not left yet. No proximity
   check, because saying you left early is never in your own favour. */

import { endpoint, ok, readBody, dbError, HttpError } from "./_lib/http.js";
import { rest } from "./_lib/supabase.js";
import { hashDevice } from "./_lib/auth.js";
import { requireEvent, findAttendeeByDevice, publicAttendee } from "./_lib/events.js";
import { alertHost } from "./_lib/alerts.js";
import * as v from "./_lib/validate.js";

export default endpoint(["POST"], async (req, res) => {
  const body = await readBody(req);
  const code = v.requireCode(body.code);
  const hash = hashDevice(v.deviceId(body.deviceId));
  const event = await requireEvent(code);

  if (event.ended_at) throw new HttpError(410, "This event has ended.", "ended");

  const result = await rest("uwuhere_attendees", {
    method: "PATCH",
    query: {
      event_id: `eq.${event.id}`,
      device_hash: `eq.${hash}`,
      left_early_at: "is.null",
      select: "id,name,note,method,distance_m,checked_in_at,left_early_at",
    },
    prefer: "return=representation",
    body: { left_early_at: new Date().toISOString() },
  });
  if (!result.ok) throw dbError(result);

  const updated = result.data?.[0];
  if (updated) {
    // The host's phones, in the Android app, if they asked (api/_lib/alerts.js).
    await alertHost(event, { kind: "left", name: updated.name });
    return ok(res, { attendee: publicAttendee(updated), already: false });
  }

  const existing = await findAttendeeByDevice(event.id, hash);
  if (!existing) {
    // Either never checked in, or checked in over P2P to a host whose page has
    // not been able to save it yet. The second is the likely one when the
    // browser believes it is checked in, and it sorts itself out.
    throw new HttpError(
      404,
      "The host has not saved your check-in yet. Try again in a minute.",
      "not-checked-in"
    );
  }
  return ok(res, { attendee: publicAttendee(existing), already: true });
});
