-- 0003_uwuhere_tap
--
-- Checking in by tapping phones: the attendee touches their phone to the
-- host's, which is running the Android app and acts as an NFC tag. The tag
-- holds a link to the join page with a one-time token on the end, which
-- main-site/api/_lib/tap.js checks.
--
--   uwuhere_events.allow_tap        the host turned tapping on
--   uwuhere_attendees.method 'tap'  a check-in made that way
--   uwuhere_attendees.tap_nonce     the token's nonce, so each tap works once
--
-- Required before deploying the site that reads allow_tap: without it every
-- API call that reads an event fails.
--
-- Safe to run more than once.


-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

alter table public.uwuhere_events
  add column if not exists allow_tap boolean not null default false;

-- At least one way to check in, now counting tapping.
alter table public.uwuhere_events
  drop constraint if exists uwuhere_events_has_method;
alter table public.uwuhere_events
  add constraint uwuhere_events_has_method check (allow_p2p or allow_location or allow_tap);


-- ---------------------------------------------------------------------------
-- Attendees
-- ---------------------------------------------------------------------------

-- 0001 left the method check unnamed, so Postgres named it.
alter table public.uwuhere_attendees
  drop constraint if exists uwuhere_attendees_method_check;
alter table public.uwuhere_attendees
  add constraint uwuhere_attendees_method_check check (method in ('p2p', 'location', 'manual', 'tap'));

-- 9 random bytes in base64url. Unique, so a token's second use is refused
-- by the database even when two arrive at once. Nulls are distinct, so every
-- other kind of check-in sits alongside.
alter table public.uwuhere_attendees
  add column if not exists tap_nonce text unique
  check (tap_nonce is null or tap_nonce ~ '^[A-Za-z0-9_-]{12}$');
