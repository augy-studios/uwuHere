/* POST /api/checkin   check in by location

   Body: { code, deviceId, name, note, position: { lat, lng, accuracy } }

   The distance is worked out here, never in the browser, and only the
   distance is stored. The attendee's coordinates are not kept.

   P2P check-ins do not come through here: the host's page records those
   through /api/host, because the host is the one who saw the device. */

import { endpoint, ok, readBody, HttpError } from "./_lib/http.js";
import { hashDevice } from "./_lib/auth.js";
import { distanceMetres } from "./_lib/geo.js";
import { requireEvent, insertAttendee, attendeeFields } from "./_lib/events.js";
import * as v from "./_lib/validate.js";

// A phone indoors commonly reports 20 to 80 m of accuracy. Up to this much of
// it is given the benefit of the doubt, so someone at the back of a hall is
// not turned away by their GPS, without letting a 2 km wifi guess pass.
const ACCURACY_ALLOWANCE_M = 100;

// Past this the reading says nothing useful about where somebody is.
const WORST_ACCURACY_M = 1000;

export default endpoint(["POST"], async (req, res) => {
  const body = await readBody(req);
  const code = v.requireCode(body.code);
  const device = v.deviceId(body.deviceId);
  const event = await requireEvent(code);

  if (event.ended_at) throw new HttpError(410, "This event has ended.", "ended");
  if (!event.allow_location) {
    throw new HttpError(403, "This event does not take check-ins by location.", "no-location");
  }
  if (event.paused) throw new HttpError(423, "The host has paused check-ins for now.", "paused");
  if (event.host_lat === null) {
    throw new HttpError(409, "The host has not set a location for this event yet.", "no-host-location");
  }

  const fields = attendeeFields(body, event);
  const here = v.position(body.position);

  if (here.accuracy > WORST_ACCURACY_M) {
    throw new HttpError(
      422,
      "Your location is too rough to check in. Turn on precise location and try again.",
      "imprecise"
    );
  }

  const distance = distanceMetres(here, { lat: event.host_lat, lng: event.host_lng });
  const allowance = Math.min(here.accuracy, ACCURACY_ALLOWANCE_M);

  if (distance - allowance > event.radius_m) {
    const away = Math.round(distance);
    throw new HttpError(
      403,
      `You look to be about ${away} m away. You need to be within ${event.radius_m} m of the host.`,
      "too-far",
      { distance: away, radius: event.radius_m }
    );
  }

  const result = await insertAttendee(event.id, {
    device_hash: hashDevice(device),
    ...fields,
    method: "location",
    distance_m: Math.round(distance),
  });

  return ok(res, result, result.already ? 200 : 201);
});
