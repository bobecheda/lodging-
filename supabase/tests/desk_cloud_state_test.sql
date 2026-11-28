-- story/desk-db-guards-2: desk_cloud_state, what the cloud holds from the
-- calling desk, and the unique rules whose refusal tells a desk it is behind
-- the cloud (lib/core/sync/desk_behind.dart, behindConstraints).
-- Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000d2', 'dev-2@desk.lodging.invalid',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now()),
       ('dev-2', '00000000-0000-0000-0000-0000000000d2', now());

create schema tests_dcs;
grant usage on schema tests_dcs to anon, authenticated;

create function tests_dcs.as_desk(p_n text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000000d' || p_n || '",'
    '"role":"authenticated","app_metadata":{"role":"desk","device_id":"dev-'
    || p_n || '"}}', true);
  perform set_config('role', 'authenticated', true);
end $$;

create function tests_dcs.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end $$;

insert into public.users (id, created_at, updated_at, device_id, full_name,
  username, role, must_change_password) values
  ('u-1', now(), now(), 'dev-1', 'Mary', 'mary', 'receptionist', false);

-- What the desk sent before its file was replaced by an older copy: a
-- closed shift, an open one, two receipts and three audit rows.
insert into public.shifts (id, created_at, updated_at, device_id, user_id,
  opened_at, opening_float, status, closed_at, expected_cash, expected_paybill,
  counted_cash, variance, first_count, close_note, closed_by, needs_review) values
  ('s-closed', now(), now(), 'dev-1', 'u-1', now(), 0, 'closed', now(),
   1400, 0, 1400, 0, 1400, null, 'u-1', false);
insert into public.shifts (id, created_at, updated_at, device_id, user_id,
  opened_at, opening_float, status) values
  ('s-open', now(), now(), 'dev-1', 'u-1', now(), 0, 'open');
insert into public.payments (id, created_at, updated_at, device_id,
  receipt_number, shift_id, received_by, received_at, amount, method) values
  ('p-50', now(), now(), 'dev-1', 'R-000050', 's-closed', 'u-1', now(), 700, 'cash'),
  ('p-52', now(), now(), 'dev-1', 'R-000052', 's-open', 'u-1', now(), 700, 'cash'),
  ('p-9', now(), now(), 'dev-1', 'R-000009', 's-closed', 'u-1', now(), 700, 'cash');
insert into public.audit_log (id, created_at, updated_at, device_id, at,
  operation_id, user_id, action, entity, entity_id, after_json) values
  ('a-1', '2026-11-11T08:03:57Z', now(), 'dev-1', now(), 'op-1', 'u-1',
   'shift.close', 'shifts', 's-closed', '{}'),
  ('a-2', '2026-11-11T08:06:05Z', now(), 'dev-1', now(), 'op-2', 'u-1',
   'shift.open', 'shifts', 's-open', '{}'),
  ('a-3', '2026-11-11T08:22:31Z', now(), 'dev-1', now(), 'op-3', 'u-1',
   'user.auto_lock', 'users', 'u-1', '{}'),
  ('a-phone', '2026-11-12T09:00:00Z', now(), 'phone-1', now(), 'op-4', 'u-1',
   'refund.reject', 'refund_decisions', 'rd-1', '{}');

-- ── Checks ─────────────────────────────────────────────────────────────

select tests_dcs.as_desk('1');

select is(
  (public.desk_cloud_state('2026-11-11T08:03:57Z') ->> 'newer_audit_rows')::int,
  2, 'counts only this desk''s audit rows newer than the file''s newest');
select is(
  (public.desk_cloud_state('2026-11-11T08:03:57Z') ->> 'last_audit_at')::timestamptz,
  '2026-11-11T08:22:31Z'::timestamptz, 'this desk''s newest audit row');
select is(
  public.desk_cloud_state('2026-11-11T08:03:57Z') ->> 'top_receipt',
  'R-000052', 'the highest receipt number, compared as a number');
select is(
  public.desk_cloud_state('2026-11-11T08:03:57Z') ->> 'open_shift',
  's-open', 'this desk''s open shift');
select is(
  (public.desk_cloud_state(null) ->> 'newer_audit_rows')::int,
  3, 'a file with no audit rows of its own: every one counts');
select is(
  (public.desk_cloud_state('2026-11-11T08:22:31Z') ->> 'newer_audit_rows')::int,
  0, 'a file as new as the cloud: none');

select tests_dcs.as_desk('2');
select is(
  public.desk_cloud_state(null),
  '{"newer_audit_rows": 0, "last_audit_at": null, "top_receipt": null, "open_shift": null}'::jsonb,
  'another desk sees only its own, here nothing');

select tests_dcs.as_anon();
select throws_ok(
  $$ select public.desk_cloud_state(null) $$, '42501', null,
  'no one without a desk''s sign-in may ask');

reset role;

-- The refusals that prove a desk is behind (desk_behind.dart).
select has_index('public', 'payments', 'payments_receipt_number_key',
  'payments_receipt_number_key exists');
select has_index('public', 'refunds', 'refunds_receipt_number_key',
  'refunds_receipt_number_key exists');
select has_index('public', 'shifts', 'shifts_one_open_per_device',
  'shifts_one_open_per_device exists');

select * from finish();
rollback;
