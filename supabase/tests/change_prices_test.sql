-- owner-app-2 (20261027000000_change_prices.sql): the owner's price edits
-- save only over the price they started from. Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner@lodging.test',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_c;
grant usage on schema tests_c to anon, authenticated;

create function tests_c.act(p_who text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case p_who
    when 'desk' then '{"sub":"00000000-0000-0000-0000-0000000000d1",'
      '"role":"authenticated","app_metadata":{"role":"desk","device_id":"dev-1"}}'
    else '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated",'
      '"app_metadata":{"role":"owner","user_id":"u-owner"}}' end, true);
  perform set_config('role', 'authenticated', true);
end $$;

-- One change, as the caller sends it.
create function tests_c.change(p_category text, p_expected integer,
  p_price integer, p_at timestamptz, p_device text) returns jsonb
language sql as $$
  select public.change_prices(jsonb_build_array(jsonb_build_object(
    'category_id', p_category, 'expected', p_expected, 'price', p_price)),
    p_at, p_device)
$$;

insert into public.users (id, created_at, updated_at, device_id, full_name,
  username, role, must_change_password) values
  ('u-owner', now(), now(), 'dev-1', 'Amina Owner', 'owner', 'owner', false),
  ('u-sup', now(), now(), 'dev-1', 'Grace Supervisor', 'grace', 'supervisor', false);
insert into public.bed_categories (id, created_at, updated_at, device_id, name,
  price_per_night, sort_order) values
  ('c-dlx', now(), now(), 'dev-1', 'Deluxe', 700, 1),
  ('c-vip', now(), now(), 'dev-1', 'VIP', 1000, 2),
  ('c-cmf', now(), now(), 'dev-1', 'Comfort', 600, 3);

create table tests_c.answers (name text primary key, answer jsonb);
grant select, insert on tests_c.answers to authenticated;

-- ── Who may change prices ──────────────────────────────────────────────

set local role anon;
select throws_ok($$select tests_c.change('c-dlx', 700, 750, now(), 'x')$$,
  '42501', null, 'anon can''t change prices');
reset role;
select tests_c.act('desk');
select throws_ok($$select tests_c.change('c-dlx', 700, 750, now(), 'dev-1')$$,
  '42501', 'only the owner can do this', 'the desk''s own sign-in can''t');
reset role;

-- ── A change over the price it started from ────────────────────────────

select tests_c.act('owner');
insert into tests_c.answers values ('phone-edit', public.change_prices(
  '[{"category_id":"c-dlx","expected":700,"price":750}]',
  '2026-10-24T06:29:00Z', 'phone-1',
  '[{"id":"a-1","created_at":"2026-10-24T06:29:00Z",
     "updated_at":"2026-10-24T06:29:00Z","device_id":"phone-1",
     "at":"2026-10-24T06:29:00Z","operation_id":"op-1","user_id":"u-owner",
     "action":"price.update","entity":"bed_categories","entity_id":"c-dlx",
     "before_json":"{\"price_per_night\":700}",
     "after_json":"{\"price_per_night\":750}"}]'));
reset role;

select is((select answer ->> 'status' from tests_c.answers where name = 'phone-edit'),
  'changed', 'the phone''s edit over 700 goes in');
select is((select price_per_night from public.bed_categories where id = 'c-dlx'),
  750, 'the price is now 750');
select is((select price_updated_at from public.bed_categories where id = 'c-dlx'),
  '2026-10-24T06:29:00Z'::timestamptz, 'stamped with the time sent');
select is((select count(*) from public.audit_log where id = 'a-1'), 1::bigint,
  'with the phone''s audit row');

select tests_c.act('owner');
insert into tests_c.answers values ('retry', tests_c.change('c-dlx', 700, 750,
  '2026-10-24T06:29:00Z', 'phone-1'));
reset role;
select is((select answer ->> 'status' from tests_c.answers where name = 'retry'),
  'changed', 'the same change again (a lost answer) is a no-op');

-- ── Losing the race ────────────────────────────────────────────────────

-- The desk still thinks Deluxe is 700.
select tests_c.act('owner');
insert into tests_c.answers values ('desk-late', tests_c.change('c-dlx', 700,
  800, '2026-10-24T06:30:00Z', 'dev-1'));
reset role;
select is((select answer - 'changed_at' from tests_c.answers where name = 'desk-late'),
  '{"status":"stale","category_id":"c-dlx","current_price":750,
    "changed_on":"phone"}'::jsonb,
  'an edit over a price that moved on is refused: where and what it is now');
select is((select (answer ->> 'changed_at')::timestamptz from tests_c.answers
  where name = 'desk-late'), '2026-10-24T06:29:00Z'::timestamptz, 'and when');
select is((select price_per_night from public.bed_categories where id = 'c-dlx'),
  750, 'nothing was overwritten');

-- The desk edits VIP; then the phone, still on the old price, loses.
select tests_c.act('owner');
select tests_c.change('c-vip', 1000, 1100, '2026-10-24T07:00:00Z', 'dev-1');
insert into tests_c.answers values ('phone-late', tests_c.change('c-vip', 1000,
  1200, '2026-10-24T07:01:00Z', 'phone-1'));
reset role;
select is((select answer ->> 'changed_on' from tests_c.answers where name = 'phone-late'),
  'desk', 'a desk edit first says "on the desk"');

-- An approval after the last edit: where the approval was made.
insert into public.price_requests (id, created_at, updated_at, device_id,
  category_id, old_price, new_price, requested_by, requested_at) values
  ('pr-1', now(), now(), 'dev-1', 'c-vip', 1100, 1150, 'u-sup', now());
select tests_c.act('owner');
select public.decide_price_request('pd-1', 'pr-1', 'approved', null,
  '2026-10-24T08:00:00Z', 'phone-1');
insert into tests_c.answers values ('after-approval', tests_c.change('c-vip',
  1100, 1300, '2026-10-24T08:05:00Z', 'dev-1'));
reset role;
select is((select answer ->> 'changed_on' || ' ' || (answer ->> 'current_price')
  from tests_c.answers where name = 'after-approval'),
  'phone 1150', 'an approval later than the last edit says where it was made');

-- ── All or nothing ─────────────────────────────────────────────────────

select tests_c.act('owner');
insert into tests_c.answers values ('mixed', public.change_prices(
  '[{"category_id":"c-cmf","expected":600,"price":650},
    {"category_id":"c-dlx","expected":700,"price":800}]',
  '2026-10-24T09:00:00Z', 'phone-1'));
reset role;
select is((select answer ->> 'status' from tests_c.answers where name = 'mixed'),
  'stale', 'one stale category refuses the save');
select is((select price_per_night from public.bed_categories where id = 'c-cmf'),
  600, 'and the other category wasn''t changed either');

select tests_c.act('owner');
insert into tests_c.answers values ('missing', tests_c.change('c-none', 1, 2,
  now(), 'phone-1'));
reset role;
select is((select answer from tests_c.answers where name = 'missing'),
  '{"status":"missing","category_id":"c-none"}'::jsonb,
  'a category not in the cloud yet is missing');

select tests_c.act('owner');
select throws_ok($$select tests_c.change('c-cmf', 600, 0, now(), 'phone-1')$$,
  '23514', null, 'a price of 0 is refused');
reset role;

select ok(
  not has_table_privilege('authenticated', 'app_private.price_changes', 'SELECT'),
  'nobody reads where prices were changed but the function');

select * from finish();
rollback;
