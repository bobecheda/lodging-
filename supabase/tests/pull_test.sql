-- sync-2: the desk's pull, the heartbeat's clock offset, and the rule that
-- every write of a pulled row takes the lodging.owner_writes lock first.
-- Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner@lodging.test',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_p;
grant usage on schema tests_p to anon, authenticated;

create function tests_p.act(p_who text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case p_who
    when 'desk' then '{"sub":"00000000-0000-0000-0000-0000000000d1",'
      '"role":"authenticated","app_metadata":{"role":"desk","device_id":"dev-1"}}'
    else '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated",'
      '"app_metadata":{"role":"owner","user_id":"u-owner"}}' end, true);
  perform set_config('role', 'authenticated', true);
end $$;

insert into public.users (id, created_at, updated_at, device_id, full_name,
  username, role, must_change_password) values
  ('u-owner', now(), now(), 'dev-1', 'Amina Owner', 'owner', 'owner', false),
  ('u-sup', now(), now(), 'dev-1', 'Grace Supervisor', 'grace', 'supervisor', false);
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
insert into public.stays (id, created_at, updated_at, device_id, guest_id, bed_id,
  check_in_at, paid_until, checked_out_at, status, checked_in_by, checked_out_by,
  room_number, bed_label) values
  ('st-1', now(), now(), 'dev-1', 'g-1', 'b-1', now(), now() + interval '3 days',
   now(), 'closed', 'u-sup', 'u-sup', '5', 'A');
insert into public.refunds (id, created_at, updated_at, device_id, stay_id, nights,
  price_per_night, amount, requested_by, requested_at) values
  ('rf-1', now(), now(), 'dev-1', 'st-1', 2, 700, 1400, 'u-sup', now());
insert into public.price_requests (id, created_at, updated_at, device_id,
  category_id, old_price, new_price, requested_by, requested_at) values
  ('pr-1', now(), now(), 'dev-1', 'c-1', 700, 750, 'u-sup', now());
-- One audit row from this desk, one from the owner's phone.
insert into public.audit_log (id, created_at, updated_at, device_id, at,
  operation_id, user_id, action, entity, entity_id, after_json) values
  ('a-desk', now(), now(), 'dev-1', now(), 'op-1', 'u-sup', 'price.request',
   'price_requests', 'pr-1', '{}'),
  ('a-phone', now(), now(), 'phone-1', now(), 'op-2', 'u-owner', 'refund.reject',
   'refund_decisions', 'rd-1', '{}');

-- The owner decides on the phone: a refund, a price request (which prices).
select tests_p.act('owner');
select public.decide_refund('rd-1', 'rf-1', 'rejected', 'Guest stays on', now(),
  'phone-1');
select public.decide_price_request('pd-1', 'pr-1', 'approved', null, now(),
  'phone-1');
reset role;

create table tests_p.pulled as select null::jsonb as page;
grant select, insert, update on tests_p.pulled to authenticated;

-- ── Who may pull ───────────────────────────────────────────────────────

set local role anon;
select throws_ok($$select public.pull_changes(0)$$, '42501', null,
  'anon can''t pull');
reset role;
select tests_p.act('owner');
select throws_ok($$select public.pull_changes(0)$$, '42501',
  'only the desk can do this', 'the owner doesn''t pull (the phone reads)');
reset role;

-- ── What comes back ────────────────────────────────────────────────────

select tests_p.act('desk');
update tests_p.pulled set page = public.pull_changes(0);
reset role;

select is(
  (select jsonb_agg(r -> 'table' order by (r ->> 'seq')::bigint)
   from tests_p.pulled, jsonb_array_elements(page -> 'rows') r
   where r ->> 'table' <> 'audit_log'),
  '["refund_decisions", "price_decisions", "bed_categories"]'::jsonb,
  'the decisions and the new price, in the order they were written');
select ok(
  (select bool_and(seq > prev) from (
     select (e.v ->> 'seq')::bigint as seq,
       lag((e.v ->> 'seq')::bigint) over (order by e.i) as prev
     from tests_p.pulled,
       jsonb_array_elements(page -> 'rows') with ordinality as e(v, i)) x
   where prev is not null),
  'rows come in server_seq order');
select is(
  (select array_agg(k order by k) from tests_p.pulled,
     jsonb_array_elements(page -> 'rows') r, jsonb_object_keys(r -> 'row') k
   where r ->> 'table' = 'bed_categories'),
  array['id', 'price_per_night', 'price_updated_at'],
  'a category comes back as its price only');
select is(
  (select jsonb_agg(r -> 'row' -> 'id') from tests_p.pulled,
     jsonb_array_elements(page -> 'rows') r where r ->> 'table' = 'audit_log'),
  '["a-phone"]'::jsonb,
  'other devices'' audit rows come back, never this desk''s own');
select ok(
  (select (page ->> 'server_time')::timestamptz >= now() from tests_p.pulled),
  'the server''s time comes back (clock_timestamp)');
select is((select page -> 'more' from tests_p.pulled), 'false'::jsonb,
  'all of it fit in one page');

select tests_p.act('desk');
update tests_p.pulled set page = public.pull_changes(0, 1);
reset role;
select ok(
  (select jsonb_array_length(page -> 'rows') = 1 and (page -> 'more')::boolean
   from tests_p.pulled),
  'a page of one says there''s more');

select tests_p.act('desk');
update tests_p.pulled set page = public.pull_changes(
  (select max(server_seq) from public.audit_log) + 1000000);
reset role;
select is((select jsonb_array_length(page -> 'rows') from tests_p.pulled), 0,
  'after the cursor: nothing');

-- ── The heartbeat's clock offset ───────────────────────────────────────

select tests_p.act('desk');
select public.desk_heartbeat(0, now(), null, '1.0.0', -720);
reset role;
select is((select clock_offset_seconds from public.desk_status
  where device_id = 'dev-1'), -720, 'the heartbeat keeps the PC''s clock offset');
select ok(
  to_regprocedure('public.desk_heartbeat(integer,timestamptz,text,text)') is null,
  'the old heartbeat (without the offset) is gone');

-- ── Every write of a pulled row takes the lock first ──────────────────
-- A function writes pulled rows if it inserts into or updates a pulled
-- table, passes rows to insert_audit, or applies the owner's tables. The
-- lock must come before that first write.

create function tests_p.pulled_writers() returns table (fn text, locked boolean)
language sql as $$
  with writes as (
    select p.oid::regprocedure::text as fn, p.prosrc as src,
      '(insert\s+into|update)\s+public\.(refund_decisions|price_decisions'
      '|bed_categories|audit_log)\M|insert_audit\s*\('
      '|apply_rows\s*\(\s*p_rows\s*,\s*app_private\.owner_tables\(\)' as pattern
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app_private', 'tests_p')
      and p.proname not in ('upsert_row', 'apply_rows', 'insert_audit',
        'pulled_writers')
  )
  select fn,
    coalesce(nullif(strpos(src,
      'pg_advisory_xact_lock(hashtext(''lodging.owner_writes''))'), 0), 2147483647)
      < regexp_instr(src, pattern, 1, 1, 0, 'i')
  from writes where src ~* pattern
$$;

select is_empty(
  $$select fn from tests_p.pulled_writers() where not locked$$,
  'every function writing a pulled row takes the lock before writing');
select ok(
  (select array_agg(fn) from tests_p.pulled_writers()) @> array[
    'decide_refund(text,text,text,text,timestamp with time zone,text,jsonb)',
    'decide_price_request(text,text,text,text,timestamp with time zone,text,jsonb)',
    'set_prices(jsonb,timestamp with time zone)',
    'import_owner_rows(text,jsonb)'],
  'the check sees the known writers');

create function tests_p.sneaky() returns void language sql as $$
  insert into public.refund_decisions (id, created_at, updated_at, device_id,
    refund_id, decision, decided_by, decided_at)
  values ('x', now(), now(), 'x', 'rf-1', 'approved', 'u-owner', now())
$$;
select is(
  (select array_agg(fn) from tests_p.pulled_writers() where not locked),
  array['tests_p.sneaky()'],
  'a writer without the lock is caught');

select * from finish();
rollback;
