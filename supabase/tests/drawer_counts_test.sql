-- Story B2 (20261110000200_drawer_counts.sql): drawer checks and
-- collections, checked as the desk checks them. Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_c2;
grant usage on schema tests_c2 to anon, authenticated;

create function tests_c2.as_desk() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated",'
    '"app_metadata":{"role":"desk","device_id":"dev-1"}}', true);
  perform set_config('role', 'authenticated', true);
end $$;

-- A check or collection as the desk sends it, with [p_extra] on top.
create function tests_c2.push(
  p_id text, p_kind text, p_by text, p_present text,
  p_extra jsonb default '{}'
) returns integer language sql as $$
  select public.push_changes(jsonb_build_array(jsonb_build_object(
    'table', 'drawer_events',
    'row', jsonb_build_object('id', p_id, 'kind', p_kind, 'counted_by', p_by,
      'present_user', p_present, 'shift_id', 's-1', 'first_count', 2700,
      'counted', 2700, 'expected', 2700, 'removed', 0, 'note', null,
      'needs_review', false, 'counted_at', '2026-11-16T09:00:00Z',
      'created_at', '2026-11-16T09:00:00Z',
      'updated_at', '2026-11-16T09:00:00Z', 'device_id', 'dev-1') || p_extra)))
$$;

insert into public.users (id, created_at, updated_at, device_id, full_name,
  username, role, must_change_password) values
  ('u-owner', now(), now(), 'dev-1', 'Amina Owner', 'owner', 'owner', false),
  ('u-sup', now(), now(), 'dev-1', 'Grace Supervisor', 'grace', 'supervisor', false),
  ('u-desk', now(), now(), 'dev-1', 'Mary Desk', 'mary', 'receptionist', false),
  ('u-tom', now(), now(), 'dev-1', 'Tom Desk', 'tom', 'receptionist', false);
insert into public.shifts (id, created_at, updated_at, device_id, user_id,
  opened_at, opening_float, status) values
  ('s-1', now(), now(), 'dev-1', 'u-desk', now(), 2000, 'open');

-- ── Checks ─────────────────────────────────────────────────────────────

select tests_c2.as_desk();
select lives_ok($$select tests_c2.push('d-1', 'check', 'u-sup', 'u-desk')$$,
  'the supervisor checks the drawer with the receptionist on shift present');
select lives_ok($$select tests_c2.push('d-1', 'check', 'u-sup', 'u-desk')$$,
  'a replayed check is a no-op');
select throws_ok($$select tests_c2.push('d-x1', 'check', 'u-desk', 'u-tom')$$,
  '42501', null, 'a receptionist doesn''t count the drawer');
select throws_ok($$select tests_c2.push('d-x2', 'check', 'u-sup', 'u-tom')$$,
  '23514', null, 'with a shift open, its receptionist is the one present');
select throws_ok($$select tests_c2.push('d-x3', 'check', 'u-sup', 'u-owner',
  '{"shift_id":null}')$$,
  '23514', null, 'the owner is never the one present');
select throws_ok($$select tests_c2.push('d-x4', 'check', 'u-sup', 'u-sup')$$,
  '23514', null, 'nobody counts alone: the counter isn''t the one present');
select throws_ok($$select tests_c2.push('d-x5', 'check', 'u-sup', 'u-desk',
  '{"first_count":null}')$$,
  '23514', null, 'a check keeps its first count');
select throws_ok($$select tests_c2.push('d-x6', 'check', 'u-owner', 'u-desk',
  '{"counted":2650,"first_count":2600,"needs_review":true,"note":"  "}')$$,
  '23514', null, 'a gap needs its reason');
select lives_ok($$select tests_c2.push('d-2', 'check', 'u-owner', 'u-desk',
  '{"counted":2650,"first_count":2600,"needs_review":true,"note":"Change from my pocket"}')$$,
  'a gap with its reason is kept, needing review');

-- ── Collections ────────────────────────────────────────────────────────

select throws_ok($$select tests_c2.push('d-x7', 'collect', 'u-owner', 'u-desk',
  '{"removed":2701}')$$,
  '23514', null, 'a collection never takes more than was counted');
select lives_ok($$select tests_c2.push('d-3', 'collect', 'u-owner', 'u-desk',
  '{"removed":2500}')$$,
  'the owner collects with the receptionist present');
reset role;
select is((select string_agg(id || ':' || needs_review::text, ',' order by id)
           from public.drawer_events),
  'd-1:false,d-2:true,d-3:false', 'what arrived, with the review flag');

select * from finish();
rollback;
