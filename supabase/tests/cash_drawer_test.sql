-- Story B1 (20261110000000_cash_drawer.sql, 20261110000100_cash_drawer_defaults.sql):
-- the blind close's first count while open, the drawer's counts, and rows
-- that arrive without the v10 columns. Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner@lodging.test',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_k;
grant usage on schema tests_k to anon, authenticated;

create function tests_k.act(p_who text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case p_who
    when 'desk' then '{"sub":"00000000-0000-0000-0000-0000000000d1",'
      '"role":"authenticated","app_metadata":{"role":"desk","device_id":"dev-1"}}'
    else '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated",'
      '"app_metadata":{"role":"owner","user_id":"u-owner"}}' end, true);
  perform set_config('role', 'authenticated', true);
end $$;

-- A row as the desk sends it.
create function tests_k.push(p_table text, p_row jsonb) returns integer
language sql as $$
  select public.push_changes(jsonb_build_array(jsonb_build_object(
    'table', p_table,
    'row', p_row || jsonb_build_object('created_at', '2026-11-10T06:00:00Z',
      'updated_at', coalesce(p_row ->> 'updated_at', '2026-11-10T06:00:00Z'),
      'device_id', 'dev-1'))))
$$;

create function tests_k.event(
  p_id text, p_kind text, p_by text, p_present text, p_counted integer,
  p_expected integer default null, p_removed integer default 0
) returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'kind', p_kind, 'counted_by', p_by,
    'present_user', p_present, 'shift_id', null, 'first_count', null,
    'counted', p_counted, 'expected', p_expected, 'removed', p_removed,
    'note', null, 'needs_review', false,
    'counted_at', '2026-11-10T06:00:00Z')
$$;

insert into public.users (id, created_at, updated_at, device_id, full_name,
  username, role, must_change_password) values
  ('u-owner', now(), now(), 'dev-1', 'Amina Owner', 'owner', 'owner', false),
  ('u-sup', now(), now(), 'dev-1', 'Grace Supervisor', 'grace', 'supervisor', false),
  ('u-desk', now(), now(), 'dev-1', 'Mary Desk', 'mary', 'receptionist', false);

-- ── 1. Shifts: the first count while open ──────────────────────────────

select tests_k.act('desk');
select lives_ok($$select tests_k.push('shifts', '{"id":"s-1","user_id":"u-desk",
  "opened_at":"2026-11-10T05:00:00Z","opening_float":2000,"status":"open",
  "first_count":1900,"opened_from":"d-1","needs_review":false}')$$,
  'an open shift may hold its first count (a count that didn''t match)');
select throws_ok($$select tests_k.push('shifts', '{"id":"s-2","user_id":"u-desk",
  "opened_at":"2026-11-10T05:00:00Z","opening_float":0,"status":"closed",
  "closed_at":"2026-11-10T06:00:00Z","expected_cash":0,"expected_paybill":0,
  "counted_cash":0,"variance":0,"closed_by":"u-desk","first_count":null}')$$,
  '23514', null, 'a closed shift still needs its first count');
select lives_ok($$select tests_k.push('shifts', '{"id":"s-1","user_id":"u-desk",
  "opened_at":"2026-11-10T05:00:00Z","opening_float":2000,"status":"closed",
  "closed_at":"2026-11-10T07:00:00Z","expected_cash":2700,"expected_paybill":0,
  "counted_cash":2650,"variance":-50,"closed_by":"u-desk","first_count":1900,
  "close_note":"Change from my pocket","opened_from":"d-1","needs_review":true,
  "updated_at":"2026-11-10T07:00:00Z"}')$$,
  'the close arrives with its review flag');
reset role;
select is((select needs_review::text || ' ' || opened_from
           from public.shifts where id = 's-1'),
  'true d-1', 'needs_review and opened_from are kept');

-- A shift row queued before the desk's v10 upgrade has no needs_review:
-- it gets the default instead of stopping the queue.
select tests_k.act('desk');
select lives_ok($$select tests_k.push('shifts', '{"id":"s-old","user_id":"u-desk",
  "opened_at":"2026-11-09T05:00:00Z","opening_float":0,"status":"closed",
  "closed_at":"2026-11-09T06:00:00Z","expected_cash":0,"expected_paybill":0,
  "counted_cash":0,"variance":0,"closed_by":"u-desk","first_count":0}')$$,
  'a shift row from before v10 (no needs_review) is accepted');
reset role;
select is((select needs_review from public.shifts where id = 's-old'), false,
  'it needs no review');

-- ── 2. The drawer's counts ─────────────────────────────────────────────

select tests_k.act('desk');
select throws_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-x1', 'start', 'u-desk', null, 2000))$$,
  '42501', null, 'a receptionist doesn''t count the drawer');
select lives_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-1', 'start', 'u-sup', null, 2000))$$,
  'the supervisor counts the starting cash');
select lives_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-1', 'start', 'u-sup', null, 2000))$$,
  'a replayed count is a no-op');
select throws_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-x2', 'start', 'u-owner', null, 5000))$$,
  '23514', null, 'the starting cash is counted once');
select throws_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-x3', 'check', 'u-sup', null, 2000, 2000))$$,
  '23514', null, 'a check needs the receptionist present');
select throws_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-x4', 'check', 'u-sup', 'u-sup', 2000, 2000))$$,
  '23514', null, 'the counter can''t be the one present');
select throws_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-x5', 'collect', 'u-owner', 'u-desk', 2000, 2000, 2500))$$,
  '23514', null, 'a collection never takes more than was counted');
select lives_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-1', 'start', 'u-sup', null, 9999) ||
  '{"updated_at":"2026-11-11T06:00:00Z"}')$$,
  'a changed count is ignored (insert-only), not an error');
reset role;
select is((select counted from public.drawer_events where id = 'd-1'), 2000,
  'the count never changes');
select tests_k.act('desk');
select lives_ok($$select tests_k.push('drawer_events',
  tests_k.event('d-2', 'check', 'u-sup', 'u-desk', 2000, 2000)
  - 'removed' - 'needs_review')$$,
  'a count without removed or needs_review is accepted');
reset role;
select is((select removed::text || ' ' || needs_review::text
           from public.drawer_events where id = 'd-2'),
  '0 false', 'it gets their defaults');

-- ── 3. Who reads them ──────────────────────────────────────────────────

select tests_k.act('desk');
select is((select count(*)::int from public.drawer_events), 0,
  'a desk can''t read the drawer''s counts');
reset role;

select * from finish();
rollback;
