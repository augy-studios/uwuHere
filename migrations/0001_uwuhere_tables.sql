-- 0001_uwuhere_tables
--
-- The two tables uwuHere owns: events, and the people who checked in to them.
--
-- Only the serverless functions in main-site/api/ touch these, through
-- PostgREST with the service role key. The browser never talks to Supabase.
--
-- Required: without this file every API call fails and no event can be made.
--
-- Safe to run more than once.


-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

create table if not exists public.uwuhere_events (
  id              uuid             primary key default gen_random_uuid(),

  -- The six character code attendees type or scan. The same alphabet as
  -- CODE_ALPHABET in main-site/api/_lib/validate.js and main-site/js/p2p.js:
  -- no vowels, no 0 O 1 I.
  code            text             not null unique
                                   check (code ~ '^[BCDFGHJKLMNPQRSTVWXYZ2-9]{6}$'),

  title           text             not null default ''
                                   check (char_length(title) <= 80),

  -- The text on the big button. Capped so it always fits inside the circle.
  button_label    text             not null default 'I''m here'
                                   check (char_length(button_label) between 1 and 20),

  -- Lowercase #rrggbb, normalised by the API.
  button_color    text             not null default '#ccffcc'
                                   check (button_color ~ '^#[0-9a-f]{6}$'),

  -- What the optional second field on the attendee form is called, for
  -- example "Student ID". Null means the field is not shown.
  note_label      text             check (note_label is null or char_length(note_label) between 1 and 40),

  allow_p2p       boolean          not null default true,
  allow_location  boolean          not null default false,

  -- Where the host was when location check-in was set up.
  host_lat        double precision check (host_lat is null or host_lat between -90 and 90),
  host_lng        double precision check (host_lng is null or host_lng between -180 and 180),
  host_accuracy_m real             check (host_accuracy_m is null or host_accuracy_m >= 0),
  radius_m        integer          not null default 100
                                   check (radius_m between 20 and 2000),

  -- scrypt, formatted by hashPassword() in main-site/api/_lib/auth.js. Null
  -- means the host page opens only in the browser that made the event.
  password_hash   text,

  paused          boolean          not null default false,
  created_at      timestamptz      not null default now(),

  -- Set by End Event. The event is closed from that moment and the row is
  -- marked for deletion: 0002 purges it seven days later.
  ended_at        timestamptz,

  constraint uwuhere_events_has_method check (allow_p2p or allow_location),
  constraint uwuhere_events_location_pair check ((host_lat is null) = (host_lng is null))
);

comment on table public.uwuhere_events is
  'uwuHere attendance events. Written only by the uwuHere serverless functions.';
comment on column public.uwuhere_events.ended_at is
  'When the host pressed End Event. Non-null means closed and marked for deletion.';

-- The purge in 0002 looks rows up both ways.
create index if not exists uwuhere_events_ended_at_idx
  on public.uwuhere_events (ended_at)
  where ended_at is not null;

create index if not exists uwuhere_events_open_created_at_idx
  on public.uwuhere_events (created_at)
  where ended_at is null;


-- ---------------------------------------------------------------------------
-- Attendees
-- ---------------------------------------------------------------------------

create table if not exists public.uwuhere_attendees (
  id             uuid        primary key default gen_random_uuid(),
  event_id       uuid        not null references public.uwuhere_events (id) on delete cascade,

  -- SHA-256 of a random id the attendee's browser keeps. The raw id never
  -- reaches the host or this table. Null for someone the host added by hand.
  device_hash    text        check (device_hash is null or device_hash ~ '^[0-9a-f]{64}$'),

  name           text        not null check (char_length(name) between 1 and 60),
  note           text        check (note is null or char_length(note) between 1 and 120),

  method         text        not null check (method in ('p2p', 'location', 'manual')),

  -- For a location check-in, how far from the host it was made, in metres.
  -- The attendee's coordinates themselves are never stored.
  distance_m     real        check (distance_m is null or distance_m >= 0),

  checked_in_at  timestamptz not null default now(),
  left_early_at  timestamptz,

  -- One check-in per browser per event. Nulls are distinct, so any number of
  -- hand-added rows can sit alongside.
  constraint uwuhere_attendees_one_per_device unique (event_id, device_hash)
);

comment on table public.uwuhere_attendees is
  'uwuHere check-ins. Deleted with their event.';

create index if not exists uwuhere_attendees_event_time_idx
  on public.uwuhere_attendees (event_id, checked_in_at);


-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
--
-- Row level security on, with no policy, on purpose. The service role key
-- bypasses RLS, and it is the only key the app uses. With no policy, a leaked
-- anon key reaches nothing here. The revokes are belt and braces on top.

alter table public.uwuhere_events    enable row level security;
alter table public.uwuhere_attendees enable row level security;

revoke all on table public.uwuhere_events    from anon, authenticated;
revoke all on table public.uwuhere_attendees from anon, authenticated;
