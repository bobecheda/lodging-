-- AD-7 voids (20261029000000_voids.sql): the cloud checks a void as the
-- desk does, and the desk reports the voids it holds. Run by
-- `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_v;
grant usage on schema tests_v to anon, authenticated;

create function tests_v.as_desk() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated",'
    '"app_metadata":{"role":"desk","device_id":"dev-1"}}', true);
  perform set_config('role', 'authenticated', true);
end $$;

-- A void as the desk sends it.
create function tests_v.push_void(
  p_id text, p_type text, p_target text, p_by text, p_reason text default 'Duplicate'
) returns integer language sql as $$
  select public.push_changes(jsonb_build_array(jsonb_build_object(
    'table', 'voids',
    'row', jsonb_build_object('id', p_id, 'target_type', p_type,
      'target_id', p_target, 'reason', p_reason, 'voided_by', p_by,
      'voided_at', '2026-11-09T18:00:00Z', 'created_at', '2026-11-09T18:00:00Z',
      'updated_at', '2026-11-09T18:00:00Z', 'device_id', 'dev-1'))))
$$;

insert into public.users (id, created_at, updated_at, device_id, full_name,
  username, role, must_change_password, is_active) values
  ('u-owner', now(), now(), 'dev-1', 'Amina Owner', 'owner', 'owner', false, true),
  ('u-sup', now(), now(), 'dev-1', 'Grace Supervisor', 'grace', 'supervisor', false, true),
  ('u-desk', now(), now(), 'dev-1', 'Mary Desk', 'mary', 'receptionist', false, true),
  -- Disabled after voiding, with the void still queued.
  ('u-gone', now(), now(), 'dev-1', 'Old Supervisor', 'old', 'supervisor', false, false);
insert into public.bed_categories (id, created_at, updated_at, device_id, name,
  price_per_night, sort_order) values
  ('c-1', now(), now(), 'dev-1', 'Deluxe', 700, 1);
insert into public.rooms (id, created_at, updated_at, device_id, room_number)
  values ('r-1', now(), now(), 'dev-1', '4');
insert into public.beds (id, created_at, updated_at, device_id, room_id, label,
  category_id, cleanliness) values
  ('b-1', now(), now(), 'dev-1', 'r-1', 'A', 'c-1', 'clean'),
  ('b-2', now(), now(), 'dev-1', 'r-1', 'B', 'c-1', 'clean');
insert into public.guests (id, created_at, updated_at, device_id, full_name, phone)
  values ('g-1', now(), now(), 'dev-1', 'Peter Kamau', '0711000482');
-- One open shift per device: Mary's is closed, the supervisor's open.
insert into public.shifts (id, created_at, updated_at, device_id, user_id,
  opened_at, opening_float, status, closed_at, expected_cash,
  expected_paybill, counted_cash, variance, first_count, closed_by) values
  ('s-1', now(), now(), 'dev-1', 'u-desk', now(), 0, 'closed', now(), 2800, 0,
   2800, 0, 2800, 'u-desk');
insert into public.shifts (id, created_at, updated_at, device_id, user_id,
  opened_at, opening_float, status) values
  ('s-2', now(), now(), 'dev-1', 'u-sup', now(), 0, 'open');
-- st-1: Mary's check-in (p-1) and the supervisor's extension (p-2).
-- st-2: checked out early with a refund (p-3).
insert into public.stays (id, created_at, updated_at, device_id, guest_id, bed_id,
  check_in_at, paid_until, checked_out_at, status, checked_in_by, checked_out_by,
  room_number, bed_label) values
  ('st-1', now(), now(), 'dev-1', 'g-1', 'b-1', now(), now() + interval '2 days',
   null, 'active', 'u-desk', null, '4', 'A'),
  ('st-2', now(), now(), 'dev-1', 'g-1', 'b-2', now(), now() + interval '3 days',
   now(), 'closed', 'u-desk', 'u-desk', '4', 'B');
insert into public.payments (id, created_at, updated_at, device_id,
  receipt_number, shift_id, received_by, received_at, amount, method) values
  ('p-1', now(), now(), 'dev-1', 'R-000001', 's-1', 'u-desk', now(), 700, 'cash'),
  ('p-2', now(), now(), 'dev-1', 'R-000002', 's-2', 'u-sup', now(), 700, 'cash'),
  ('p-3', now(), now(), 'dev-1', 'R-000003', 's-1', 'u-desk', now(), 2100, 'cash');
insert into public.stay_charges (id, created_at, updated_at, device_id, stay_id,
  payment_id, kind, nights, price_per_night, amount, period_start, period_end,
  category_id, category_name) values
  ('sc-1', now(), now(), 'dev-1', 'st-1', 'p-1', 'check_in', 1, 700, 700,
   now(), now() + interval '1 day', 'c-1', 'Deluxe'),
  ('sc-2', now(), now(), 'dev-1', 'st-1', 'p-2', 'extension', 1, 700, 700,
   now() + interval '1 day', now() + interval '2 days', 'c-1', 'Deluxe'),
  ('sc-3', now(), now(), 'dev-1', 'st-2', 'p-3', 'check_in', 3, 700, 2100,
   now(), now() + interval '3 days', 'c-1', 'Deluxe');
insert into public.refunds (id, created_at, updated_at, device_id, stay_id, nights,
  price_per_night, amount, requested_by, requested_at) values
  ('rf-1', now(), now(), 'dev-1', 'st-2', 2, 700, 1400, 'u-desk', now());

-- ── 1. Who voids ───────────────────────────────────────────────────────

select tests_v.as_desk();
select throws_ok($$select tests_v.push_void('v-x1', 'payment', 'p-1', 'u-desk')$$,
  '42501', null, 'a receptionist does not void');
select throws_ok($$select tests_v.push_void('v-x2', 'payment', 'p-2', 'u-sup')$$,
  '42501', null, 'nobody voids a payment they took');
select throws_ok($$select tests_v.push_void('v-x3', 'stay', 'st-1', 'u-desk')$$,
  '42501', null, 'nobody voids a stay they checked in (nor a receptionist)');
select lives_ok($$select tests_v.push_void('v-1', 'payment', 'p-2', 'u-owner')$$,
  'the owner voids the supervisor''s payment');
select lives_ok($$select tests_v.push_void('v-2', 'payment', 'p-1', 'u-gone')$$,
  'a supervisor disabled after voiding: the void still goes up (role, not '
  'is_active)');
reset role;
select is((select count(*)::int from public.voids), 2, 'two voids arrived');

-- ── 2. What is voided ──────────────────────────────────────────────────

select tests_v.as_desk();
select throws_ok(
  $$select tests_v.push_void('v-x4', 'payment', 'p-1', 'u-sup', '   ')$$,
  '23514', null, 'a reason is required');
select throws_ok(
  $$select tests_v.push_void('v-x5', 'payment', 'p-1', 'u-sup', repeat('x', 201))$$,
  '23514', null, 'a reason is at most 200 characters');
select throws_ok($$select tests_v.push_void('v-x6', 'payment', 'p-404', 'u-sup')$$,
  '23503', null, 'the payment must be in the cloud');
select throws_ok($$select tests_v.push_void('v-x7', 'refund', 'rf-1', 'u-sup')$$,
  '23514', null, 'refund payouts are not voided');
select throws_ok($$select tests_v.push_void('v-x8', 'stay', 'st-2', 'u-sup')$$,
  '23514', null, 'a stay with a refund is not voided');
select throws_ok($$select tests_v.push_void('v-x9', 'payment', 'p-3', 'u-sup')$$,
  '23514', null, 'nor a payment of a stay with a refund');
select throws_ok($$select tests_v.push_void('v-x10', 'payment', 'p-1', 'u-owner')$$,
  '23505', null, 'a payment is voided once (unique target)');
select lives_ok($$select tests_v.push_void('v-1', 'payment', 'p-2', 'u-owner')$$,
  'a replayed void is a no-op, not a refusal');
reset role;

-- ── 3. The heartbeat says how many voids the desk holds ────────────────

select tests_v.as_desk();
select public.desk_heartbeat(0, now(), null, '1.1.0', 0, 2);
reset role;
select is((select voids_held from public.desk_status where device_id = 'dev-1'),
  2, 'the desk reports the voids it holds');
select tests_v.as_desk();
select public.desk_heartbeat(0, now(), null, '1.1.0', 0);
reset role;
select is((select voids_held from public.desk_status where device_id = 'dev-1'),
  0, 'an older desk''s heartbeat (no count) reports none');

select * from finish();
rollback;
