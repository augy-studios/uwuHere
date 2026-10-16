/* GET /api/event?code=BCDFGH   what an attendee's page needs

   With an X-Uwuhere-Device header carrying the browser's device id, also
   answers whether that browser has checked in and left, as `me`. A header
   rather than a query parameter, so the id stays out of access logs. */

import { endpoint, ok } from "./_lib/http.js";
import { hashDevice } from "./_lib/auth.js";
import { requireEvent, publicEvent, findAttendeeByDevice } from "./_lib/events.js";
import * as v from "./_lib/validate.js";

export default endpoint(["GET"], async (req, res) => {
  const code = v.requireCode(req.query?.code);
  const row = await requireEvent(code);
  const data = publicEvent(row);

  const device = req.headers["x-uwuhere-device"];
  if (typeof device === "string" && device) {
    const mine = await findAttendeeByDevice(row.id, hashDevice(v.deviceId(device)));
    data.me = mine ? { checkedInAt: mine.checked_in_at, leftEarlyAt: mine.left_early_at } : null;
  }

  return ok(res, data);
});
