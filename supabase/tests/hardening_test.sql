-- Cloud hardening (20261024000000_hardening.sql). Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_h;
grant usage on schema tests_h to anon, authenticated;

create function tests_h.as_desk() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated",'
    '"app_metadata":{"role":"desk","device_id":"dev-1"}}', true);
  perform set_config('role', 'authenticated', true);
end $$;

-- A whole row as the desk sends it, at [p_at].
create function tests_h.push(p_table text, p_row jsonb, p_at text) returns integer
language sql as $$
  select public.push_changes(jsonb_build_array(jsonb_build_object(
    'table', p_table,
    'row', p_row || jsonb_build_object('created_at', '2026-10-22T06:00:00Z',
      'updated_at', p_at, 'device_id', 'dev-1'))))
$$;

insert into public.users (id, created_at, updated_at, device_id, full_name,
  username, role, must_change_password) values
  ('u-1', now(), now(), 'dev-1', 'Mary', 'mary', 'receptionist', false);
insert into public.bed_categories (id, created_at, updated_at, device_id, name,
  price_per_night, sort_order) values
  ('c-1', now(), now(), 'dev-1', 'Deluxe', 700, 1);
insert into public.rooms (id, created_at, updated_at, device_id, room_number)
  values ('r-1', now(), now(), 'dev-1', '5');
insert into public.beds (id, created_at, updated_at, device_id, room_id, label,
  category_id, cleanliness) values
  ('b-1', now(), now(), 'dev-1', 'r-1', 'A', 'c-1', 'clean');
insert into public.guests (id, created_at, updated_at, device_id, full_name, phone)
  values ('g-1', now(), now(), 'dev-1', 'Peter Kamau', '0711000482');
insert into public.shifts (id, created_at, updated_at, device_id, user_id,
  opened_at, opening_float, status) values
  ('s-1', now(), now(), 'dev-1', 'u-1', now(), 0, 'open');
insert into public.stays (id, created_at, updated_at, device_id, guest_id, bed_id,
  check_in_at, paid_until, status, checked_in_by, room_number, bed_label) values
  ('st-1', now(), now(), 'dev-1', 'g-1', 'b-1', now(), now() + interval '2 days',
   'active', 'u-1', '5', 'A');

create table tests_h.payment as select
  '{"id":"p-1","receipt_number":"R-000001","shift_id":"s-1","received_by":"u-1",
   "received_at":"2026-10-22T06:00:00Z","amount":1400,"method":"cash",
   "mpesa_code":null,"print_count":0}'::jsonb as row;
create table tests_h.charge as select
  '{"id":"sc-1","stay_id":"st-1","payment_id":"p-1","kind":"check_in","nights":2,
   "price_per_night":700,"amount":1400,"period_start":"2026-10-22T06:00:00Z",
   "period_end":"2026-10-24T07:00:00Z","category_id":"c-1",
   "category_name":"Deluxe"}'::jsonb as row;
create table tests_h.void as select
  '{"id":"v-1","target_type":"payment","target_id":"p-1","reason":"Typo",
   "voided_by":"u-1","voided_at":"2026-10-22T07:00:00Z"}'::jsonb as row;
grant select on tests_h.payment, tests_h.charge, tests_h.void to authenticated;

-- ── 1. Payments, charges and voids never change once in the cloud ─────

select tests_h.as_desk();
select tests_h.push('payments', (select row from tests_h.payment), '2026-10-22T06:00:00Z');
select tests_h.push('stay_charges', (select row from tests_h.charge), '2026-10-22T06:00:00Z');
select tests_h.push('voids', (select row from tests_h.void), '2026-10-22T07:00:00Z');
select tests_h.push('payments',
  (select row || '{"amount":9999,"method":"paybill","mpesa_code":"QJK7H2LM4P"}'
   from tests_h.payment), '2026-10-22T09:00:00Z');
reset role;
select is((select amount || ' ' || method from public.payments where id = 'p-1'),
  '1400 cash', 'a payment''s changed amount and method are ignored');

select tests_h.as_desk();
select tests_h.push('payments',
  (select row || '{"print_count":2}' from tests_h.payment), '2026-10-22T10:00:00Z');
reset role;
select is((select print_count from public.payments where id = 'p-1'), 2,
  'a higher print_count is accepted');

select tests_h.as_desk();
select tests_h.push('payments',
  (select row || '{"print_count":1}' from tests_h.payment), '2026-10-22T11:00:00Z');
select tests_h.push('stay_charges',
  (select row || '{"nights":3,"amount":2100}' from tests_h.charge),
  '2026-10-22T11:00:00Z');
select tests_h.push('voids',
  (select row || '{"reason":"Changed my mind"}' from tests_h.void),
  '2026-10-22T11:00:00Z');
reset role;
select is((select print_count from public.payments where id = 'p-1'), 2,
  'a lower print_count is ignored, even with a newer updated_at');
select is((select nights from public.stay_charges where id = 'sc-1'), 2,
  'a stay charge never changes');
select is((select reason from public.voids where id = 'v-1'), 'Typo',
  'a void never changes');

-- ── 2. Install codes expire after 7 days ──────────────────────────────

create temp table made as select app_private.new_install_code() as text;
select matches((select text from made),
  '^[2-9A-Z]{4}-[2-9A-Z]{4}-[2-9A-Z]{4} · expires [A-Z][a-z]{2} [0-9]{1,2} '
  '[A-Z][a-z]{2} [0-9]{4}, [0-9]{2}:[0-9]{2} \(Nairobi\)$',
  'a new code comes with its expiry in Nairobi time');
create temp table code as select split_part(text, ' ', 1) as code from made;
select ok(public.install_code_unused((select code from code)), 'a fresh code works');
select ok((select expires_at between now() + interval '7 days' - interval '1 minute'
  and now() + interval '7 days' from app_private.install_codes
  order by created_at desc limit 1), 'it expires in 7 days');
update app_private.install_codes set expires_at = now() - interval '1 minute';
select ok(not public.install_code_unused((select code from code)),
  'an expired code is refused');
select throws_ok(
  format($$select public.register_desk(%L, 'dev-2',
    '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000a1',
    'u-owner', 'owner@example.com')$$, (select code from code)),
  '42501', 'install code not valid, expired or already used',
  'register_desk refuses an expired code');

-- ── 3. connect-desk's rate limit ──────────────────────────────────────

select public.record_connect_attempt('Owner@Example.com ', false)
from generate_series(1, 9);
select ok(public.connect_attempt_allowed('owner@example.com'),
  '9 failed tries in the hour: still allowed');
select public.record_connect_attempt('owner@example.com', false);
select ok(not public.connect_attempt_allowed('OWNER@example.com'),
  'the 10th failure locks the email out');
update app_private.connect_attempts set at = now() - interval '61 minutes';
select ok(public.connect_attempt_allowed('owner@example.com'),
  'failures older than an hour don''t count');
select public.record_connect_attempt('owner@example.com', true)
from generate_series(1, 12);
select ok(public.connect_attempt_allowed('owner@example.com'),
  'successful tries don''t count');

set local role authenticated;
select throws_ok($$select public.connect_attempt_allowed('x@example.com')$$,
  '42501', null, 'only the Edge Function (service role) checks attempts');
reset role;

-- ── 6. Fixed search paths ─────────────────────────────────────────────

select ok((select array_to_string(proconfig, ',') like '%search_path=%'
  from pg_proc where oid = 'app_private.synced_tables()'::regprocedure)
  and (select array_to_string(proconfig, ',') like '%search_path=%'
  from pg_proc where oid = 'app_private.owner_tables()'::regprocedure),
  'synced_tables() and owner_tables() have a fixed search path');

select * from finish();
rollback;
