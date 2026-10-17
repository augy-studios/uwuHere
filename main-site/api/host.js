/* POST /api/host   everything the host page does

   Body: { code, hostKey, action, ... }

     get                             the event and its attendees
     record   { deviceHash, name, note, at, method }
                                     a check-in the host's page received: by
                                     same wifi (method "p2p", the default),
                                     through the app's hotspot ("hotspot"), or
                                     from the app on the attendee's phone over
                                     Nearby Connections ("mesh")
     add      { name, note, at }     somebody added by hand
     remove   { attendeeId }
     pause / resume
     update   { settings }           any of the fields eventSettings() reads
     password { password }           set, change, or clear with ""
     end                             close the event and mark it for deletion

   `record` and `add` answer { attendee, already }. Everything else answers
   the whole { event, attendees } snapshot, so the page redraws from one
   source of truth rather than patching its copy.

   An ended event is read only: `get` still works, so the list can be
   downloaded until the purge, and everything else answers 410. */

import { endpoint, ok, readBody, dbError, HttpError } from "./_lib/http.js";
import { rest } from "./_lib/supabase.js";
import { isHostKey, hashPassword } from "./_lib/auth.js";
import { checkHostPassword } from "./_lib/password.js";
import {
  requireEvent, hostEvent, listAttendees, insertAttendee, attendeeFields, eventSettings,
} from "./_lib/events.js";
import * as v from "./_lib/validate.js";

export default endpoint(["POST"], async (req, res) => {
  const body = await readBody(req);
  const code = v.requireCode(body.code);
  let event = await requireEvent(code);

  if (!isHostKey(event.id, body.hostKey)) {
    throw new HttpError(403, "This browser cannot manage that event.", "not-host");
  }

  const action = String(body.action || "get");

  if (action === "get") return snapshot(res, event);

  if (event.ended_at) throw new HttpError(410, "This event has ended.", "ended");

  switch (action) {
    case "record": {
      // No pause check: the host's page decided when it took the check-in,
      // and one queued while offline may arrive after a pause.
      const result = await insertAttendee(event.id, {
        device_hash: v.deviceHash(body.deviceHash),
        ...attendeeFields(body, event),
        method: ["hotspot", "mesh"].includes(body.method) ? body.method : "p2p",
        checked_in_at: v.pastTime(body.at, event.created_at),
      });
      return ok(res, result, result.already ? 200 : 201);
    }

    case "add": {
      const result = await insertAttendee(event.id, {
        device_hash: null,
        name: v.text(body.name, "The name", { min: 1, max: v.LIMITS.name }),
        note: v.optionalText(body.note, "The note", { max: v.LIMITS.note }),
        method: "manual",
        checked_in_at: v.pastTime(body.at, event.created_at),
      });
      return ok(res, result, 201);
    }

    case "remove": {
      const result = await rest("uwuhere_attendees", {
        method: "DELETE",
        query: { id: `eq.${v.uuid(body.attendeeId, "attendee")}`, event_id: `eq.${event.id}` },
        prefer: "return=minimal",
      });
      if (!result.ok) throw dbError(result);
      return snapshot(res, event);
    }

    case "pause":
    case "resume":
      event = await patchEvent(event, { paused: action === "pause" });
      return snapshot(res, event);

    case "update":
      event = await patchEvent(event, eventSettings(body.settings ?? {}, event));
      return snapshot(res, event);

    case "password": {
      const password_hash = body.password
        ? await hashPassword(await checkHostPassword(body.password, { title: event.title, code: event.code }))
        : null;
      event = await patchEvent(event, { password_hash });
      return snapshot(res, event);
    }

    case "end":
      event = await patchEvent(event, { ended_at: new Date().toISOString() });
      return snapshot(res, event);

    default:
      throw new HttpError(400, "Unknown action.", "bad-action");
  }
});

async function patchEvent(event, columns) {
  if (Object.keys(columns).length === 0) return event;

  const result = await rest("uwuhere_events", {
    method: "PATCH",
    query: { id: `eq.${event.id}` },
    prefer: "return=representation",
    body: columns,
  });
  if (!result.ok) throw dbError(result);
  return result.data?.[0] ?? { ...event, ...columns };
}

async function snapshot(res, event) {
  return ok(res, { event: hostEvent(event), attendees: await listAttendees(event.id) });
}
