/* GET /api/cron/purge   the daily clean-up

   Run by Vercel Cron (vercel.json), which sends CRON_SECRET as a bearer
   token. Deletes events ended over 7 days ago and events over 30 days old
   that were never ended; migrations/0002_uwuhere_purge.sql holds the rule. */

import { endpoint, ok, dbError, HttpError } from "../_lib/http.js";
import { rest } from "../_lib/supabase.js";

export default endpoint(["GET"], async (req, res) => {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.authorization !== `Bearer ${secret}`) {
    throw new HttpError(401, "Not allowed.", "unauthorised");
  }

  const result = await rest("rpc/uwuhere_purge_events", { method: "POST", body: {} });
  if (!result.ok) throw dbError(result);

  console.log(`[uwuhere] purge removed ${result.data} event(s)`);
  return ok(res, { removed: result.data });
});
