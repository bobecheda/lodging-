-- The cloud's rules: who may read and write, the sync functions, and the
-- mirrored desk rules. Run by `supabase test db` (CI job "cloud").
begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000d2', 'dev-2@desk.lodging.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner@example.com', 'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id) values
  ('dev-1', '00000000-0000-0000-0000-0000000000d1');

create schema tests;
grant usage on schema tests to anon, authenticated;

-- Claims for the three callers.
create function tests.desk() returns text language sql as $$
  select '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated",'
    '"app_metadata":{"role":"desk","device_id":"dev-1"}}'
$$;
create function tests.stranger_desk() returns text language sql as $$
  select '{"sub":"00000000-0000-0000-0000-0000000000d2","role":"authenticated",'
    '"app_metadata":{"role":"desk","device_id":"dev-2"}}'
$$;
create function tests.owner() returns text language sql as $$
  select '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated",'
    '"app_metadata":{"role":"owner","user_id":"u-owner"}}'
$$;

-- One row in the shape the desk sends: {table, row}.
create function tests.item(p_table text, p_row jsonb) returns jsonb language sql as $$
  select jsonb_build_object('table', p_table, 'row', p_row)
$$;
create function tests.stamped(p_id text, p_at text default '2026-10-22T06:00:00Z')
returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'created_at', p_at, 'updated_at', p_at,
    'device_id', 'dev-1')
$$;

create table tests.snapshot as select jsonb_build_array(
  tests.item('users', tests.stamped('u-owner') || '{"full_name":"Amina Owner",
    "username":"owner","password_hash":"never-stored","role":"owner",
    "is_active":true,"must_change_password":false}'),
  tests.item('users', tests.stamped('u-sup') || '{"full_name":"Grace Supervisor",
    "username":"grace","role":"supervisor","is_active":true,
    "must_change_password":false}'),
  tests.item('bed_categories', tests.stamped('c-deluxe') || '{"name":"Deluxe",
    "price_per_night":700,"sort_order":1,"is_active":true}'),
  tests.item('rooms', tests.stamped('r-5') || '{"room_number":"5","is_active":true}'),
  tests.item('beds', tests.stamped('b-5a') || '{"room_id":"r-5","label":"A",
    "category_id":"c-deluxe","cleanliness":"clean","is_active":true}'),
  tests.item('guests', tests.stamped('g-1') || '{"full_name":"Peter Kamau",
    "phone":"0711000482","id_type":"national_id","id_number":"12345678"}'),
  tests.item('shifts', tests.stamped('s-1') || '{"user_id":"u-sup",
    "opened_at":"2026-10-22T06:00:00Z","opening_float":0,"status":"open"}'),
  tests.item('stays', tests.stamped('st-1') || '{"guest_id":"g-1","bed_id":"b-5a",
    "check_in_at":"2026-10-22T06:00:00Z","paid_until":"2026-10-25T07:00:00Z",
    "checked_out_at":"2026-10-23T07:30:00Z","status":"closed","checked_in_by":"u-sup",
    "checked_out_by":"u-sup","room_number":"5","bed_label":"A"}'),
  -- Paid already: the snapshot sends final states.
  tests.item('refunds', tests.stamped('rf-1') || '{"stay_id":"st-1","nights":2,
    "price_per_night":700,"amount":1400,"requested_by":"u-sup",
    "requested_at":"2026-10-23T07:30:00Z","method":"cash","shift_id":"s-1",
    "paid_by":"u-sup","paid_at":"2026-10-23T08:00:00Z","receipt_number":"R-000002",
    "print_count":0}'),
  tests.item('price_requests', tests.stamped('pr-1') || '{"category_id":"c-deluxe",
    "old_price":700,"new_price":750,"requested_by":"u-sup",
    "requested_at":"2026-10-22T06:00:00Z"}'),
  tests.item('audit_log', tests.stamped('a-1') || '{"at":"2026-10-22T06:00:00Z",
    "operation_id":"op-1","user_id":"u-sup","action":"price.request",
    "entity":"price_requests","entity_id":"pr-1","after_json":"{}"}')
) as rows;
grant select on tests.snapshot to authenticated;

-- Switches to [claims] as an authenticated caller; `reset role` goes back.
create function tests.act(p_claims text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', p_claims, true);
  perform set_config('role', 'authenticated', true);
end $$;

-- ── Nobody else gets in ────────────────────────────────────────────────

set local role anon;
select throws_ok('select count(*) from public.users', '42501',
  null, 'anon reads nothing');
select throws_ok($$select public.push_changes('[]')$$, '42501',
  null, 'anon calls no sync function');
reset role;

select tests.act(tests.stranger_desk());
select throws_ok($$select public.import_desk_rows('[]')$$, '42501',
  'this desk is not connected', 'a desk token for an unregistered device is refused');
reset role;

-- ── The first upload: desk part ────────────────────────────────────────

select tests.act(tests.desk());
select throws_ok($$select public.push_changes('[]')$$, '55000',
  'the first upload is not finished', 'push waits for the first upload');
select is(public.import_desk_rows((select rows from tests.snapshot)), 11,
  'the desk imports its snapshot, final states included');
select is(public.import_desk_rows((select rows from tests.snapshot)), 11,
  'a re-sent batch is harmless');
select throws_ok(
  $$select public.import_desk_rows(jsonb_build_array(tests.item('refund_decisions',
    tests.stamped('d-1') || '{"refund_id":"rf-1","decision":"approved",
    "decided_by":"u-owner","decided_at":"2026-10-23T07:45:00Z"}')))$$,
  '42501', null, 'the desk never writes decisions');
select throws_ok('insert into public.rooms (id) values (''r-x'')', '42501',
  null, 'no direct writes');
select is((select count(*)::int from public.guests), 0,
  'the desk can''t read guests');
reset role;

select is((select count(*)::int from public.users), 2, 'rows arrived once');
select ok((select to_jsonb(u) ? 'password_hash' from public.users u limit 1) is false,
  'no password hash in the cloud');

-- ── The first upload: owner part ───────────────────────────────────────

select tests.act(tests.owner());
select throws_ok($$select public.push_changes('[]')$$, '42501',
  'only the desk can do this', 'the owner can''t push desk rows');
select is(public.import_owner_rows('dev-1', jsonb_build_array(tests.item(
  'refund_decisions', tests.stamped('d-1') || '{"refund_id":"rf-1",
  "decision":"approved","decided_by":"u-owner","decided_at":"2026-10-23T07:45:00Z"}'))),
  1, 'the owner imports the desk''s earlier decisions');
select is((select count(*)::int from public.guests), 1, 'the owner reads guests');
select lives_ok($$select public.finish_first_upload('dev-1')$$, 'the owner finishes the upload');
-- Each call is its own transaction in production; here the import's flag
-- would outlive it.
select set_config('app.importing', 'off', true);
select throws_ok($$select public.import_owner_rows('dev-1', '[]')$$, '55000',
  null, 'the owner import happens once');
reset role;

-- ── The desk's push ────────────────────────────────────────────────────

select tests.act(tests.desk());
select throws_ok($$select public.import_desk_rows('[]')$$, '55000',
  null, 'the import is closed once finished');
select is(public.push_changes(jsonb_build_array(tests.item('rooms',
  tests.stamped('r-5', '2026-10-22T06:00:00Z') ||
  '{"room_number":"5","floor":"OLD","is_active":true}'))), 1, 'an older copy is accepted…');
reset role;
select is((select floor from public.rooms where id = 'r-5'), null, '…and ignored');
select tests.act(tests.desk());
select is(public.push_changes(jsonb_build_array(tests.item('rooms',
  tests.stamped('r-5', '2026-10-22T09:00:00Z') ||
  '{"room_number":"5","floor":"1st","is_active":true}'))), 1, 'a newer one is applied');
select is(public.push_changes(jsonb_build_array(tests.item('bed_categories',
  tests.stamped('c-deluxe', '2026-10-22T09:00:00Z') ||
  '{"name":"Deluxe","price_per_night":999,"sort_order":1,"is_active":false}'))), 1,
  'the desk closes a category');
select throws_ok($$select public.push_changes(jsonb_build_array(tests.item('rooms',
  jsonb_build_object('id','r-6','created_at','2026-10-22T06:00:00Z',
  'updated_at','2026-10-22T06:00:00Z','device_id','dev-2','room_number','6'))))$$,
  '42501', 'a desk pushes only its own rows', 'another device''s rows are refused');
select throws_like($$select public.push_changes(jsonb_build_array(tests.item('rooms',
  tests.stamped('r-bad') || '{"room_number":"lower"}')))$$,
  'rooms r-bad:%', 'a refused row names its table and id');
-- Upserts of rows already here: the insert-time checks stand aside.
select lives_ok($$select public.push_changes(jsonb_build_array(tests.item('refunds',
  tests.stamped('rf-1', '2026-10-23T09:00:00Z') || '{"stay_id":"st-1","nights":2,
  "price_per_night":700,"amount":1400,"requested_by":"u-sup",
  "requested_at":"2026-10-23T07:30:00Z","method":"cash","shift_id":"s-1",
  "paid_by":"u-sup","paid_at":"2026-10-23T08:00:00Z","receipt_number":"R-000002",
  "print_count":1}')))$$, 'a paid refund pushed again (a reprint) is accepted');
select lives_ok($$select public.push_changes(jsonb_build_array(tests.item('price_requests',
  tests.stamped('pr-1', '2026-10-22T09:30:00Z') || '{"category_id":"c-deluxe",
  "old_price":700,"new_price":750,"requested_by":"u-sup",
  "requested_at":"2026-10-22T06:00:00Z"}')))$$,
  'an open request pushed again doesn''t collide with itself');
select lives_ok($$select public.desk_heartbeat(14, now(), 'rooms r-bad: check', '1.0.0')$$,
  'the heartbeat');
select lives_ok($$select public.desk_heartbeat(0, now(), null, '1.0.0')$$,
  'the heartbeat again (upsert)');
reset role;
select is((select is_active || '/' || price_per_night from public.bed_categories
  where id = 'c-deluxe'), 'false/700', 'a category''s price never comes from the desk');
select is((select count(*)::int from public.desk_status), 1, 'one status row per desk');

-- ── The owner's decisions: the first one wins ─────────────────────────

select tests.act(tests.owner());
select is(public.decide_price_request('pd-1', 'pr-1', 'approved', null,
  '2026-10-22T10:00:00Z', 'dev-1') ->> 'status', 'decided', 'approve a price request');
select is(public.decide_price_request('pd-1', 'pr-1', 'approved', null,
  '2026-10-22T10:00:00Z', 'dev-1') ->> 'status', 'decided', 'a retry is the same decision');
select is(public.decide_price_request('pd-2', 'pr-1', 'rejected', 'No',
  '2026-10-22T10:01:00Z', 'phone') ->> 'decided_by_name', 'Amina Owner',
  'a second decision loses and learns who decided');
reset role;
select is((select price_per_night from public.bed_categories where id = 'c-deluxe'), 750,
  'approving set the price');

select tests.act(tests.desk());
select is(public.withdraw_price_request('pr-1', 'u-sup', null, '2026-10-22T10:02:00Z')
  ->> 'status', 'already_decided', 'a decided request can''t be withdrawn');
select throws_ok($$select public.decide_refund('d-9', 'rf-1', 'approved', null,
  now(), 'dev-1')$$, '42501', null, 'the desk can''t decide');
reset role;

-- ── Mirrored rules ─────────────────────────────────────────────────────

select throws_ok('delete from public.refunds', 'P0001', 'refunds rows are never deleted',
  'never deleted');
select throws_ok($$insert into public.price_requests (id, created_at, updated_at,
  device_id, category_id, old_price, new_price, requested_by, requested_at)
  values ('pr-2', now(), now(), 'dev-1', 'c-deluxe', 750, 800, 'u-sup', now()),
         ('pr-3', now(), now(), 'dev-1', 'c-deluxe', 750, 820, 'u-sup', now())$$,
  'P0001', 'the category already has an open price request', 'one open request per category');

select * from finish();
rollback;
