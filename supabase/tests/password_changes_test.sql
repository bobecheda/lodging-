-- owner-app-3 (20261028000000_password_changes.sql): the owner's password
-- changes are recorded, read only by the owner, and pulled by the desk.
-- Run by `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner@lodging.test',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000d1', now());

create schema tests_w;
grant usage on schema tests_w to anon, authenticated;

create function tests_w.act(p_who text) returns void language plpgsql as $$
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
  ('u-owner', now(), now(), 'dev-1', 'Amina Owner', 'owner', 'owner', false);

create table tests_w.kept (name text primary key, at timestamptz, page jsonb);
grant select, insert, update on tests_w.kept to authenticated;

-- ── Who may record ─────────────────────────────────────────────────────

set local role anon;
select throws_ok($$select public.record_password_change('x', 'phone-1')$$,
  '42501', null, 'anon can''t record a change');
reset role;
select tests_w.act('desk');
select throws_ok($$select public.record_password_change('x', 'dev-1')$$,
  '42501', 'only the owner can do this', 'the desk''s own sign-in can''t');
select throws_ok($$insert into public.owner_password_changes (id, created_at,
  updated_at, device_id, user_id, changed_at)
  values ('x', now(), now(), 'dev-1', 'u-owner', now())$$,
  '42501', null, 'nobody writes the table directly');
reset role;

-- ── Recording ──────────────────────────────────────────────────────────

select tests_w.act('owner');
insert into tests_w.kept (name, at) values ('first', public.record_password_change(
  'pc-1', 'phone-1',
  '[{"id":"a-1","created_at":"2026-10-25T06:00:00Z",
     "updated_at":"2026-10-25T06:00:00Z","device_id":"phone-1",
     "at":"2026-10-25T06:00:00Z","operation_id":"op-1","user_id":"u-owner",
     "action":"user.change_password","entity":"users","entity_id":"u-owner",
     "before_json":null,"after_json":"{}"}]'));
insert into tests_w.kept (name, at) values ('retry',
  public.record_password_change('pc-1', 'phone-1'));
reset role;

select ok((select at >= now() from tests_w.kept where name = 'first'),
  'stamped with the server''s time');
select is(
  (select (user_id, device_id, changed_at)::text from public.owner_password_changes
   where id = 'pc-1'),
  (select ('u-owner', 'phone-1', at)::text from tests_w.kept where name = 'first'),
  'for the signed-in owner, from the phone');
select is((select at from tests_w.kept where name = 'retry'),
  (select at from tests_w.kept where name = 'first'),
  'a retry answers the first time again');
select is((select count(*) from public.owner_password_changes), 1::bigint,
  'and records nothing more');
select is((select count(*) from public.audit_log where id = 'a-1'), 1::bigint,
  'with the phone''s audit row');

-- ── Reading and pulling ────────────────────────────────────────────────

select tests_w.act('desk');
select is((select count(*) from public.owner_password_changes), 0::bigint,
  'a desk can''t read the table');
insert into tests_w.kept (name, page) values ('pull', public.pull_changes(0));
reset role;
select is(
  (select r -> 'row' ->> 'id' from tests_w.kept,
     jsonb_array_elements(page -> 'rows') r
   where name = 'pull' and r ->> 'table' = 'owner_password_changes'),
  'pc-1', 'the desk pulls the change');
select is(
  (select array_agg(k order by k) from tests_w.kept,
     jsonb_array_elements(page -> 'rows') r, jsonb_object_keys(r -> 'row') k
   where name = 'pull' and r ->> 'table' = 'owner_password_changes'),
  array['changed_at', 'created_at', 'device_id', 'id', 'updated_at', 'user_id'],
  'when and where, never a password');

select * from finish();
rollback;
