-- owner-app-1 (20261026000000_owner_app.sql): the server's time and the
-- masked guests view. Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner@lodging.test',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_o;
grant usage on schema tests_o to anon, authenticated;

create function tests_o.act(p_who text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case p_who
    when 'desk' then '{"sub":"00000000-0000-0000-0000-0000000000d1",'
      '"role":"authenticated","app_metadata":{"role":"desk","device_id":"dev-1"}}'
    else '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated",'
      '"app_metadata":{"role":"owner","user_id":"u-owner"}}' end, true);
  perform set_config('role', 'authenticated', true);
end $$;

insert into public.guests (id, created_at, updated_at, device_id, full_name,
  phone, id_type, id_number) values
  ('g-1', now(), now(), 'dev-1', 'Peter Kamau', '0711000482', 'national_id',
   '12343921'),
  ('g-2', now(), now(), 'dev-1', 'Jane Okello', '+256712345678', null, null),
  ('g-3', now(), now(), 'dev-1', 'Short Number', '+1234567', null, null);

-- ── The server's time ──────────────────────────────────────────────────

select tests_o.act('owner');
select ok(public.server_time() >= now(), 'the owner gets the server''s time');
reset role;
set local role anon;
select throws_ok($$select public.server_time()$$, '42501', null,
  'anon can''t ask the time');
reset role;

-- ── Guests, masked ─────────────────────────────────────────────────────

select tests_o.act('owner');
select results_eq(
  $$select id, full_name, phone_masked from public.owner_guests order by id$$,
  $$values ('g-1', 'Peter Kamau', '0711 ••• 482'),
    ('g-2', 'Jane Okello', '+2567 ••• 678'), ('g-3', 'Short Number', '•••')$$,
  'the owner sees names and masked phones, as the desk masks them');
reset role;

select is(
  (select array_agg(column_name::text order by ordinal_position)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'owner_guests'),
  array['id', 'full_name', 'phone_masked'],
  'the view has no full phone and no ID number');
select ok(
  (select 'security_invoker=true' = any(reloptions) from pg_class
   where oid = 'public.owner_guests'::regclass),
  'the view runs with the caller''s rights (row-level security applies)');

select tests_o.act('desk');
select is((select count(*) from public.owner_guests), 0::bigint,
  'a desk sees no guests through the view');
reset role;

set local role anon;
select throws_ok($$select * from public.owner_guests$$, '42501', null,
  'anon can''t read the view');
reset role;

-- The view joins a computed part, so Postgres can't write through it at
-- all (55000, checked before permissions), and no write is granted anyway.
select tests_o.act('owner');
select throws_ok($$insert into public.owner_guests (id, full_name)
  values ('g-9', 'X')$$, '55000', null, 'nobody writes through the view');
reset role;

select ok(
  not has_table_privilege('authenticated', 'public.owner_guests',
    'INSERT, UPDATE, DELETE, TRUNCATE'),
  'no write is granted on the view');

select * from finish();
rollback;
