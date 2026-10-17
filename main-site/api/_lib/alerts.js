/* Check-in notifications for the host, in the Android app: "Alex checked in"
   and "Sam left early", for the two things that reach the server without the
   host's page seeing them, a check-in by location (api/checkin.js) and
   leaving early (api/leave.js). Same-wifi and hotspot check-ins arrive on
   the host's own open page, and tapping phones happens at the host's phone,
   so none of them notifies.

   **One FCM topic per event, named from its host key**: uwuhere-host- and the
   first 40 hex digits of the SHA-256 of the key. The host's phone works out
   the same name from the key it holds (js/app-notify.js) and joins it while
   "Check-ins to my events" is on. Nobody without the key can name the topic,
   so nobody else can listen in on who checks in, and nothing about phones is
   stored here.

   **Never in the way.** Without FIREBASE_SERVICE_ACCOUNT this does nothing.
   A failure is logged and swallowed, and the wait is capped, since the
   attendee is waiting on the same request. Each event's notifications share
   one tag, so a busy event updates one notification rather than stacking
   forty. */

import { createHash } from "node:crypto";
import { rest } from "./supabase.js";
import { hostKeyFor } from "./auth.js";
import { fcmConfigured, sendToTopic } from "./fcm.js";

// How long the attendee's request waits for the push. A slow FCM still
// delivers; this request just stops waiting for it.
const WAIT_MS = 3000;

export function hostTopic(eventId) {
  const hash = createHash("sha256").update(hostKeyFor(eventId)).digest("hex");
  return `uwuhere-host-${hash.slice(0, 40)}`;
}

async function checkedInCount(eventId) {
  const result = await rest("uwuhere_attendees", { query: { event_id: `eq.${eventId}`, select: "id" } });
  return result.ok && Array.isArray(result.data) ? result.data.length : null;
}

/**
 * Tells the host's phones. `kind` is "checkin" or "left", and `name` is the
 * attendee's, as they typed it.
 */
export async function alertHost(event, { kind, name }) {
  if (!fcmConfigured()) return;

  const send = async () => {
    let body;
    if (kind === "left") {
      body = `${name} left early.`;
    } else {
      const count = await checkedInCount(event.id);
      body = `${name} checked in by location.` + (count ? ` ${count} checked in so far.` : "");
    }
    await sendToTopic(hostTopic(event.id), {
      title: event.title || `Event ${event.code}`,
      body,
      data: { type: "checkin", code: event.code },
      channel: "checkins",
      tag: `event-${event.code}`,
      // Old news after an hour: a phone that was off for longer sees the list.
      ttl: 3600,
    });
  };

  try {
    await Promise.race([send(), new Promise((resolve) => setTimeout(resolve, WAIT_MS))]);
  } catch (cause) {
    console.warn("[uwuhere] host alert not sent:", cause?.message ?? cause);
  }
}
