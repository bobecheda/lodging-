-- owner-app-3: the owner's password changes, so the desk knows when its own
-- copy of the owner's password is out of date. See docs/sync.md, "The
-- owner's password".

-- One row per change, written before the password itself changes (if that
-- then fails, the desk only asks for one online sign-in, which the
-- unchanged password passes). No password or hash is ever stored here.
create table public.owner_password_changes (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  user_id text not null references public.users (id),
  changed_at timestamptz not null,
  server_seq bigint not null default nextval('public.sync_seq')
);

alter table public.owner_password_changes enable row level security;
revoke all on public.owner_password_changes from anon, authenticated;
grant select on public.owner_password_changes to authenticated;
create policy owner_password_changes_owner_reads on public.owner_password_changes
  for select to authenticated
  using ((select app_private.jwt_role()) = 'owner');

-- Records a change by the signed-in owner, at the server's time, with the
-- caller's audit rows (the phone sends its own; the desk pushes its own).
-- A retry with the same id answers the first time again. The desk pulls the
-- row, so this takes the lock first (supabase/tests/pull_test.sql).
create function public.record_password_change(
  p_id text, p_device_id text, p_audit jsonb default null
) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  v_owner text := app_private.jwt_user_id();
  v_at timestamptz := clock_timestamp();
  v_existing timestamptz;
begin
  perform app_private.require_role('owner');
  perform pg_advisory_xact_lock(hashtext('lodging.owner_writes'));
  select changed_at into v_existing from public.owner_password_changes
  where id = p_id;
  if found then
    return v_existing;
  end if;
  insert into public.owner_password_changes
    (id, created_at, updated_at, device_id, user_id, changed_at)
  values (p_id, v_at, v_at, p_device_id, v_owner, v_at);
  perform app_private.insert_audit(p_audit);
  return v_at;
end $$;

revoke execute on function public.record_password_change(text, text, jsonb)
  from public, anon;
grant execute on function public.record_password_change(text, text, jsonb)
  to authenticated;

-- ── The pull brings the changes to the desk ────────────────────────────
-- As 20261025000000_pull.sql, plus owner_password_changes (every change,
-- the desk's own included: harmless, it already knows them).
create or replace function public.pull_changes(p_after bigint, p_limit integer default 500)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_device text := app_private.require_desk();
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 1000);
  v_rows jsonb;
  v_count integer;
begin
  with changed as (
    select 'refund_decisions' as tab, d.server_seq as seq,
      to_jsonb(d) - 'server_seq' as data
    from public.refund_decisions d where d.server_seq > p_after
    union all
    select 'price_decisions', d.server_seq, to_jsonb(d) - 'server_seq'
    from public.price_decisions d where d.server_seq > p_after
    union all
    select 'bed_categories', c.server_seq, jsonb_build_object(
      'id', c.id, 'price_per_night', c.price_per_night,
      'price_updated_at', c.price_updated_at)
    from public.bed_categories c
    where c.server_seq > p_after and c.price_updated_at is not null
    union all
    select 'owner_password_changes', p.server_seq, to_jsonb(p) - 'server_seq'
    from public.owner_password_changes p where p.server_seq > p_after
    union all
    select 'audit_log', a.server_seq, to_jsonb(a) - 'server_seq'
    from public.audit_log a
    where a.server_seq > p_after and a.device_id <> v_device
  ), page as (
    select * from changed order by seq limit v_limit + 1
  )
  select
    coalesce(jsonb_agg(jsonb_build_object('table', tab, 'seq', seq, 'row', data)
      order by seq) filter (where n <= v_limit), '[]'::jsonb),
    count(*)
  into v_rows, v_count
  from (select page.*, row_number() over (order by seq) as n from page) numbered;
  return jsonb_build_object(
    'server_time', clock_timestamp(),
    'rows', v_rows,
    'more', v_count > v_limit);
end $$;
