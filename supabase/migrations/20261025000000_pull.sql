-- sync-2: the desk's pull and the clock check. See docs/sync.md.

-- ── The lock every write of a pulled row takes ─────────────────────────
-- The desk pulls refund_decisions, price_decisions, category prices
-- (bed_categories.price_per_night) and other devices' audit_log rows by
-- server_seq. A sequence value is taken when the row is written, not when it
-- commits, so a writer that commits late could land behind a desk's cursor
-- and never be pulled. Every function that writes those rows therefore takes
-- pg_advisory_xact_lock(hashtext('lodging.owner_writes')) BEFORE its first
-- write: then rows commit in server_seq order. (Desk pushes never write the
-- price column or a decision, and their audit rows aren't pulled.)
-- supabase/tests/pull_test.sql fails if a function writes a pulled table
-- without taking the lock first.

-- import_owner_rows wrote decisions without it (harmless during the first
-- upload, but the rule has no exceptions).
create or replace function public.import_owner_rows(p_device_id text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.require_role('owner');
  perform pg_advisory_xact_lock(hashtext('lodging.owner_writes'));
  if not exists (
    select 1 from app_private.devices
    where device_id = p_device_id and first_upload_done_at is null) then
    raise exception 'no first upload is waiting for this desk' using errcode = '55000';
  end if;
  perform set_config('app.importing', 'on', true);
  return app_private.apply_rows(p_rows, app_private.owner_tables());
end $$;

-- ── The pull ───────────────────────────────────────────────────────────

-- What changed for the calling desk after [p_after], oldest first, at most
-- [p_limit] rows: the owner's decisions, category prices (id, price and
-- when only; the desk's own columns never come back) and other devices'
-- audit rows. `server_time` (clock_timestamp: the time of answering) lets
-- the desk check its clock.
create function public.pull_changes(p_after bigint, p_limit integer default 500)
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

revoke execute on function public.pull_changes(bigint, integer) from public, anon;
grant execute on function public.pull_changes(bigint, integer) to authenticated;

-- ── The desk's clock in its heartbeat ──────────────────────────────────

-- The PC's clock minus the server's, in seconds (positive: the PC is fast).
alter table public.desk_status add column clock_offset_seconds integer;

drop function public.desk_heartbeat(integer, timestamptz, text, text);
create function public.desk_heartbeat(
  p_pending integer, p_last_push_at timestamptz, p_problem text,
  p_app_version text, p_clock_offset integer default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_device text := app_private.require_desk();
begin
  insert into public.desk_status as s
    (device_id, reported_at, last_push_at, pending, problem, app_version,
     clock_offset_seconds)
  values (v_device, now(), p_last_push_at, p_pending, p_problem, p_app_version,
    p_clock_offset)
  on conflict (device_id) do update set
    reported_at = excluded.reported_at, last_push_at = excluded.last_push_at,
    pending = excluded.pending, problem = excluded.problem,
    app_version = excluded.app_version,
    clock_offset_seconds = excluded.clock_offset_seconds;
end $$;

revoke execute on function public.desk_heartbeat(integer, timestamptz, text, text, integer)
  from public, anon;
grant execute on function public.desk_heartbeat(integer, timestamptz, text, text, integer)
  to authenticated;
