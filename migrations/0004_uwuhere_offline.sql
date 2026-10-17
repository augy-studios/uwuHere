-- 0004_uwuhere_offline
--
-- Two more ways a check-in is made, both for a venue with no internet:
--
--   'hotspot'   through the host's phone, as its own wifi hotspot: the
--               attendee joins it and checks in on a page the phone serves
--               (android/.../Hotspot.java). The host's page sends it on,
--               later if it has to, through /api/host like a same-wifi one.
--   'tap_late'  a tap on the host's phone made while the attendee had no
--               connection, kept in their browser and sent once they had one
--               (main-site/api/_lib/tap.js). checked_in_at is the tap's time.
--
-- Required before deploying the site that sends them: without it those
-- check-ins are refused.
--
-- Safe to run more than once.

alter table public.uwuhere_attendees
  drop constraint if exists uwuhere_attendees_method_check;
alter table public.uwuhere_attendees
  add constraint uwuhere_attendees_method_check
  check (method in ('p2p', 'location', 'manual', 'tap', 'tap_late', 'hotspot'));
