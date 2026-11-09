-- Story B1 (story/fd-11-b1-blind-close): the blind close and the drawer's
-- running ledger, mirrored from the desk's schema v10. Timestamped after
-- 20261029000000_voids (checked against the dev project's applied list).
--
-- The desk writes all of it and pushes it, in order:
-- - a shift's first count is saved while it is still open (a count that
--   didn't match), and a close records whether it needs review;
-- - a shift says which count its opening float came from (opened_from);
-- - drawer_events: the drawer's own counts by the owner or a supervisor.
--   B1 writes the starting cash ('start'); B2 adds drawer checks ('check')
--   and weekly collections ('collect'), with the receptionist present.
--   Insert-only; never edited or deleted.

-- ── 1. Shifts ──────────────────────────────────────────────────────────

alter table public.shifts
  add column needs_review boolean not null default false,
  add column opened_from text;

-- The first count may be saved while open; a closed shift still has one.
do $$
declare v_name text;
begin
  select conname into v_name from pg_constraint
  where conrelid = 'public.shifts'::regclass and contype = 'c'
    and pg_get_constraintdef(oid) like '%(first_count IS NULL)%';
  if v_name is null then
    raise exception 'the shifts first_count check was not found';
  end if;
  execute format('alter table public.shifts drop constraint %I', v_name);
end $$;
alter table public.shifts add constraint shifts_first_count_when_closed
  check (status = 'open' or first_count is not null);

-- ── 2. The drawer's counts ─────────────────────────────────────────────

create table public.drawer_events (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  kind text not null check (kind in ('start', 'check', 'collect')),
  counted_by text not null references public.users (id),
  present_user text references public.users (id),
  shift_id text references public.shifts (id),
  first_count integer,
  counted integer not null check (counted >= 0),
  expected integer,
  removed integer not null default 0,
  note text check (length(note) <= 200),
  needs_review boolean not null default false,
  counted_at timestamptz not null,
  server_seq bigint not null default nextval('public.sync_seq'),
  check (removed >= 0 and removed <= counted),
  check (kind = 'collect' or removed = 0),
  check ((kind = 'start') = (present_user is null)),
  check ((kind = 'start') = (expected is null)),
  check (present_user is null or present_user <> counted_by)
);
create index drawer_events_shift on public.drawer_events (shift_id);

create trigger drawer_events_no_delete before delete on public.drawer_events
  for each row execute function app_private.refuse('drawer_events rows are never deleted');
create trigger drawer_events_no_update before update on public.drawer_events
  for each row execute function app_private.refuse('drawer_events rows are never edited');

-- Who counts, as the desk checks it: the owner or a supervisor, by role
-- (as for voids: the users rows arrive first, in order). The starting cash
-- comes once, before any other count.
create function app_private.drawer_events_rules() returns trigger
language plpgsql set search_path = '' as $$
declare v_role text;
begin
  -- A replayed batch (or the first upload's repeat) upserts rows already
  -- here; INSERT ... ON CONFLICT fires this trigger for them too.
  if exists (select 1 from public.drawer_events where id = new.id) then
    return new;
  end if;
  select role into v_role from public.users where id = new.counted_by;
  if v_role is null or v_role not in ('owner', 'supervisor') then
    raise exception 'only the owner or a supervisor counts the drawer'
      using errcode = '42501';
  end if;
  if new.kind = 'start' and exists (
    select 1 from public.drawer_events
    where device_id = new.device_id and kind = 'start') then
    raise exception 'the starting cash was already counted'
      using errcode = '23514';
  end if;
  return new;
end $$;
create trigger drawer_events_rules before insert on public.drawer_events
  for each row execute function app_private.drawer_events_rules();

-- ── 3. Sync: a desk table, insert-only ─────────────────────────────────

create or replace function app_private.synced_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array[
    'users', 'settings', 'bed_categories', 'rooms', 'beds', 'housekeepers',
    'guests', 'shifts', 'drawer_events', 'stays', 'payments', 'stay_charges',
    'refunds', 'refund_decisions', 'price_requests', 'price_decisions',
    'housekeeping_tasks', 'inventory_items', 'inventory_movements', 'voids',
    'expenses', 'audit_log']
$$;

-- As 20261024000000_hardening.sql, with drawer_events insert-only too.
create or replace function app_private.upsert_row(p_table text, p_row jsonb) returns void
language plpgsql set search_path = '' as $$
declare
  v_pk text := case when p_table = 'settings' then 'key' else 'id' end;
  v_cols text;
  v_set text;
begin
  if not p_table = any (app_private.synced_tables()) then
    raise exception 'unknown table %', p_table;
  end if;
  select string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position)
    into v_cols
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = p_table
    and c.column_name not in ('server_seq', 'price_updated_at');
  if p_table in ('audit_log', 'stay_charges', 'voids', 'drawer_events')
    or p_table = any (app_private.owner_tables()) then
    execute format(
      'insert into public.%1$I (%2$s) select %2$s '
      'from jsonb_populate_record(null::public.%1$I, $1) '
      'on conflict (%3$I) do nothing',
      p_table, v_cols, v_pk) using p_row;
  elsif p_table = 'payments' then
    execute format(
      'insert into public.payments as t (%1$s) select %1$s '
      'from jsonb_populate_record(null::public.payments, $1) '
      'on conflict (id) do update set '
      'print_count = excluded.print_count, '
      'updated_at = greatest(t.updated_at, excluded.updated_at) '
      'where excluded.print_count > t.print_count',
      v_cols) using p_row;
  else
    select string_agg(format('%I = excluded.%I', c.column_name, c.column_name), ', ')
      into v_set
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = p_table
      and c.column_name not in ('server_seq', 'price_updated_at', 'created_at', v_pk)
      and not (p_table = 'bed_categories' and c.column_name = 'price_per_night');
    execute format(
      'insert into public.%1$I as t (%2$s) select %2$s '
      'from jsonb_populate_record(null::public.%1$I, $1) '
      'on conflict (%3$I) do update set %4$s '
      'where excluded.updated_at > t.updated_at',
      p_table, v_cols, v_pk, v_set) using p_row;
  end if;
end $$;

-- ── 4. Security: default deny; the owner reads ─────────────────────────

alter table public.drawer_events enable row level security;
revoke all on public.drawer_events from anon, authenticated;
grant select on public.drawer_events to authenticated;
create policy drawer_events_owner_reads on public.drawer_events
  for select to authenticated
  using ((select app_private.jwt_role()) = 'owner');
