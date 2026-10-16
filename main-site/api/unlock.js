/* POST /api/unlock   open the host page on another device

   Body: { code, password }
   Answers { hostKey, event, attendees }.

   Works on an ended event too, so a host can still download the list from
   another device during the seven days before it is purged. */

import { endpoint, ok, readBody, HttpError } from "./_lib/http.js";
import { hostKeyFor, verifyPassword } from "./_lib/auth.js";
import { requireEvent, hostEvent, listAttendees } from "./_lib/events.js";
import * as v from "./_lib/validate.js";

export default endpoint(["POST"], async (req, res) => {
  const body = await readBody(req);
  const code = v.requireCode(body.code);
  const event = await requireEvent(code);

  if (!event.password_hash) {
    throw new HttpError(
      403,
      "This event has no password, so it can only be managed from the browser that made it.",
      "no-password"
    );
  }

  if (typeof body.password !== "string" || !(await verifyPassword(body.password, event.password_hash))) {
    throw new HttpError(403, "That password is not right.", "wrong-password");
  }

  return ok(res, {
    hostKey: hostKeyFor(event.id),
    event: hostEvent(event),
    attendees: await listAttendees(event.id),
  });
});
