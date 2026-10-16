-- 0002_uwuhere_purge
--
-- Deletes events that are done with, and their attendees with them.
--
--   ended events     seven days after End Event
--   unended events   thirty days after they were made
--
-- The seven days give a host time to download the list again from another
-- device after ending. Both windows are repeated in the interface copy as
-- PURGE_AFTER_END_DAYS and PURGE_UNENDED_DAYS in main-site/js/store.js.
-- Change them together.
--
-- Called once a day by the Vercel Cron job in main-site/vercel.json, through
-- main-site/api/cron/purge.js. Can also be run by hand:
--
--   select public.uwuhere_purge_events();
--
-- If this is not applied the app still works; old events just stay forever,
-- and the daily cron job logs an error.
--
-- Safe to run more than once.

create or replace function public.uwuhere_purge_events()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.uwuhere_events
   where (ended_at is not null and ended_at < now() - interval '7 days')
      or (ended_at is null and created_at < now() - interval '30 days');

  get diagnostics removed = row_count;
  return removed;
end;
$$;

comment on function public.uwuhere_purge_events() is
  'Deletes uwuHere events ended over 7 days ago, or made over 30 days ago and never ended. Returns the number removed.';

-- PostgREST exposes every function in public as an RPC, and Supabase grants
-- new functions to anon by default. Only the service role may run this.
revoke all on function public.uwuhere_purge_events() from public, anon, authenticated;
grant execute on function public.uwuhere_purge_events() to service_role;
