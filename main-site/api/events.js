/* POST /api/events   make an event

   Body: the settings eventSettings() reads, plus an optional password.
   Answers 201 with { code, hostKey, event, attendees }.

   The code is drawn here rather than in the browser so that the unique index
   on uwuhere_events.code decides collisions, not two clients guessing. */

import { endpoint, ok, readBody, dbError, HttpError } from "./_lib/http.js";
import { rest } from "./_lib/supabase.js";
import { hostKeyFor, hashPassword, requireHostSecret } from "./_lib/auth.js";
import { checkHostPassword } from "./_lib/password.js";
import { eventSettings, hostEvent } from "./_lib/events.js";
import * as v from "./_lib/validate.js";

const CODE_ATTEMPTS = 6;

export default endpoint(["POST"], async (req, res) => {
  requireHostSecret();

  const body = await readBody(req);
  const settings = eventSettings(body);
  // The code is not drawn yet, and a random one could not be guessed into a
  // password anyway, so only the title is context here.
  const password_hash = body.password
    ? await hashPassword(await checkHostPassword(body.password, { title: settings.title }))
    : null;

  for (let attempt = 0; attempt < CODE_ATTEMPTS; attempt++) {
    const code = v.generateCode();
    const result = await rest("uwuhere_events", {
      method: "POST",
      prefer: "return=representation",
      body: { code, ...settings, password_hash },
    });

    // 409 is the unique index on code: draw another.
    if (result.status === 409) continue;
    if (!result.ok) throw dbError(result);

    const row = result.data[0];
    return ok(res, { code, hostKey: hostKeyFor(row.id), event: hostEvent(row), attendees: [] }, 201);
  }

  throw new HttpError(503, "Could not find a free event code. Try again.", "busy");
});
