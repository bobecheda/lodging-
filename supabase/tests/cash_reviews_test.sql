-- Story B3 (20261111000000_cash_reviews.sql): who decides a cash review,
-- once, and the desk pulls it. Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner@lodging.test',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_r;
grant usage on schema tests_r to anon, authenticated;

create function tests_r.act(p_who text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case p_who
    when 'desk' then '{"sub":"00000000-0000-0000-0000-0000000000d1",'
      '"role":"authenticated","app_metadata":{"role":"desk","device_id":"dev-1"}}'
    else '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated",'
      '"app_metadata":{"role":"owner","user_id":"u-owner"}}' end, true);
  perform set_config('role', 'authenticated', true);
end $$;

-- A decision: [p_by] is who the desk says decides (ignored for the owner).
create function tests_r.decide(
  p_id text, p_type text, p_target text, p_decision text, p_by text,
  p_reason text default null
) returns text language sql as $$
  select public.decide_cash_review(p_id, p_type, p_target, p_decision,
    p_reason, p_by, '2026-11-17T09:00:00Z', 'dev-1') ->> 'status'
$$;

insert into public.users (id, created_at, updated_at, device_id, full_name,
  username, role, must_change_password, is_active) values
  ('u-owner', now(), now(), 'dev-1', 'Amina Owner', 'owner', 'owner', false, true),
  ('u-grace', now(), now(), 'dev-1', 'Grace Supervisor', 'grace', 'supervisor', false, true),
  ('u-otto', now(), now(), 'dev-1', 'Otto Supervisor', 'otto', 'supervisor', false, true),
  ('u-gone', now(), now(), 'dev-1', 'Gone Supervisor', 'gone', 'supervisor', false, false),
  ('u-mary', now(), now(), 'dev-1', 'Mary Desk', 'mary', 'receptionist', false, true);

-- Closed shifts: Mary's (needs review), Mary's (exact), Mary's closed by
-- Grace (needs review), Grace's own (needs review).
insert into public.shifts (id, created_at, updated_at, device_id, user_id,
  opened_at, opening_float, status, closed_at, expected_cash, expected_paybill,
  counted_cash, variance, first_count, close_note, closed_by, needs_review) values
  ('s-mary', now(), now(), 'dev-1', 'u-mary', now(), 0, 'closed', now(),
   2700, 0, 2650, -50, 2600, 'Change', 'u-mary', true),
  ('s-exact', now(), now(), 'dev-1', 'u-mary', now(), 0, 'closed', now(),
   2700, 0, 2700, 0, 2700, null, 'u-mary', false),
  ('s-by-grace', now(), now(), 'dev-1', 'u-mary', now(), 0, 'closed', now(),
   2700, 0, 2650, -50, 2600, 'Change', 'u-grace', true),
  ('s-grace', now(), now(), 'dev-1', 'u-grace', now(), 0, 'closed', now(),
   2700, 0, 2650, -50, 2600, 'Change', 'u-grace', true);
-- Counts needing review: by Grace (Mary present), by the owner (Mary
-- present).
insert into public.drawer_events (id, created_at, updated_at, device_id, kind,
  counted_by, present_user, first_count, counted, expected, note, needs_review,
  counted_at) values
  ('d-grace', now(), now(), 'dev-1', 'check', 'u-grace', 'u-mary', 2600, 2650,
   2700, 'Short at the check', true, now()),
  ('d-owner', now(), now(), 'dev-1', 'check', 'u-owner', 'u-mary', 2600, 2650,
   2700, 'Short at the check', true, now());

-- ── 1. A receptionist's close: the supervisor on the desk ──────────────

select tests_r.act('desk');
select is(tests_r.decide('r-1', 'shift', 's-mary', 'approved', 'u-grace'),
  'decided', 'the desk decides a receptionist''s close for the supervisor');
select is(tests_r.decide('r-1', 'shift', 's-mary', 'approved', 'u-grace'),
  'decided', 'the same decision again is a no-op');
select is(tests_r.decide('r-x', 'shift', 's-mary', 'rejected', 'u-otto', 'No'),
  'already_decided', 'decided once: the first decision wins');

-- ── 2. Who may not decide (each a bypass attempt) ──────────────────────

select throws_ok($$select tests_r.decide('r-2', 'shift', 's-by-grace',
  'approved', 'u-mary')$$, '42501', null, 'a receptionist never decides');
select throws_ok($$select tests_r.decide('r-2', 'shift', 's-by-grace',
  'approved', 'u-owner')$$, '42501', null,
  'the desk can''t decide in the owner''s name');
select throws_ok($$select tests_r.decide('r-2', 'shift', 's-by-grace',
  'approved', 'u-gone')$$, '42501', null, 'a disabled supervisor can''t');
select throws_ok($$select tests_r.decide('r-2', 'shift', 's-grace',
  'approved', 'u-grace')$$, '42501', null, 'nobody decides their own shift');
select throws_ok($$select tests_r.decide('r-2', 'shift', 's-by-grace',
  'approved', 'u-grace')$$, '42501', null,
  'nobody decides a close they made');
select throws_ok($$select tests_r.decide('r-2', 'shift', 's-grace',
  'approved', 'u-otto')$$, '42501', null,
  'a supervisor''s shift is the owner''s, not another supervisor''s');
select throws_ok($$select tests_r.decide('r-2', 'shift', 's-by-grace',
  'approved', 'u-otto')$$, '42501', null,
  'a close made by a supervisor is the owner''s to decide');
select throws_ok($$select tests_r.decide('r-2', 'drawer_event', 'd-grace',
  'approved', 'u-otto')$$, '42501', null,
  'a supervisor''s count is the owner''s to decide');
select throws_ok($$select tests_r.decide('r-2', 'drawer_event', 'd-owner',
  'approved', 'u-otto')$$, '42501', null,
  'the owner''s own count is the owner''s to decide');

-- ── 3. What may not be decided ─────────────────────────────────────────

select throws_ok($$select tests_r.decide('r-3', 'shift', 's-exact',
  'approved', 'u-otto')$$, '23514', null, 'nothing to review');
select is(tests_r.decide('r-3', 'shift', 's-missing', 'approved', 'u-otto'),
  'missing', 'a close not in the cloud yet');
select throws_ok($$select tests_r.decide('r-3', 'shift', 's-mary',
  'maybe', 'u-otto')$$, '22023', null, 'approved or rejected only');
reset role;

-- ── 4. The owner ───────────────────────────────────────────────────────

select tests_r.act('owner');
select throws_ok($$select tests_r.decide('r-4', 'shift', 's-grace',
  'rejected', null, '  ')$$, '23514', null, 'a rejection needs a reason');
select is(tests_r.decide('r-4', 'shift', 's-grace', 'rejected', 'u-grace',
  'The reason doesn''t explain KES 50'), 'decided',
  'the owner decides a supervisor''s shift (the named decider is ignored)');
select is(tests_r.decide('r-5', 'drawer_event', 'd-owner', 'approved', null),
  'decided', 'the owner decides a gap from the owner''s own count');
reset role;
select is((select decided_by from public.cash_reviews where id = 'r-4'),
  'u-owner', 'decided by the owner, whoever the call named');

-- ── 5. Nobody writes it directly; the desk pulls it ────────────────────

select tests_r.act('desk');
select throws_ok($$insert into public.cash_reviews (id) values ('r-x')$$,
  '42501', null, 'no direct writes');
select throws_ok($$select public.push_changes(jsonb_build_array(jsonb_build_object(
  'table', 'cash_reviews', 'row', jsonb_build_object('id', 'r-y',
  'device_id', 'dev-1'))))$$, '42501', null, 'a desk doesn''t push decisions');
select is((select count(*)::int from jsonb_array_elements(
    public.pull_changes(0) -> 'rows') r where r ->> 'table' = 'cash_reviews'),
  3, 'the desk pulls the three decisions');
reset role;

set local role anon;
select throws_ok($$select tests_r.decide('r-6', 'shift', 's-by-grace',
  'approved', 'u-otto')$$, '42501', null, 'anon can''t decide');
reset role;

select * from finish();
rollback;
