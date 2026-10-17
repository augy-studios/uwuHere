-- 0005_uwuhere_bluetooth
--
-- Checking in by Bluetooth, with the host's phone in the Android app:
--
--   uwuhere_events.allow_bluetooth   the host turned Bluetooth on
--   'bluetooth'  from Chrome on Android (Web Bluetooth): the page reads a
--                one-time token from the host's phone and sends it to
--                /api/checkin (main-site/api/_lib/tap.js)
--   'mesh'       from the uwuHere app on the attendee's phone, phone to phone
--                over Nearby Connections, needing no internet on either
--                side; the host's page records it like a same-wifi one
--
-- Required before deploying the site that reads allow_bluetooth: without it
-- every API call that reads an event fails.
--
-- Safe to run more than once.

alter table public.uwuhere_events
  add column if not exists allow_bluetooth boolean not null default false;

alter table public.uwuhere_events
  drop constraint if exists uwuhere_events_has_method;
alter table public.uwuhere_events
  add constraint uwuhere_events_has_method
  check (allow_p2p or allow_location or allow_tap or allow_bluetooth);

alter table public.uwuhere_attendees
  drop constraint if exists uwuhere_attendees_method_check;
alter table public.uwuhere_attendees
  add constraint uwuhere_attendees_method_check
  check (method in ('p2p', 'location', 'manual', 'tap', 'tap_late', 'hotspot', 'bluetooth', 'mesh'));
