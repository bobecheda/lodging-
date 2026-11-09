-- AD-7 voids (story/ad-7-voids). Voids are written on the desk only, by
-- the owner or a supervisor, checked there first (lib/features/voids/
-- domain/void_rules.dart), and pushed like any desk row. The cloud checks
-- the same rules when a void row arrives. If it still refuses one, the desk
-- holds that row aside and pushes everything after it (it never stops the
-- queue), and reports how many it holds in its heartbeat (voids_held).
--
-- Who may void is judged from public.users, which the desk pushes before
-- any void: the outbox goes up strictly in the order it was written, so the
-- cloud's users rows are, at that moment, what the desk had when the void
-- was written. Only the role is checked, not is_active: a user's current
-- is_active may be later than the void (disabled after voiding, while the
-- void was still queued offline; with AD-11, disabled from the phone), and
-- the desk only lets an active user sign in to void at all.

-- ── 1. The void rules ──────────────────────────────────────────────────

create function app_private.voids_rules() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_role text;
  v_creator text;
  v_stays text[];
begin
  -- A replayed batch (or the first upload's repeat) upserts rows already
  -- here; INSERT ... ON CONFLICT fires this trigger for them too.
  if exists (select 1 from public.voids where id = new.id) then
    return new;
  end if;
  if length(trim(new.reason)) = 0 or length(trim(new.reason)) > 200 then
    raise exception 'a void needs a reason of at most 200 characters'
      using errcode = '23514';
  end if;
  select role into v_role from public.users where id = new.voided_by;
  if v_role is null or v_role not in ('owner', 'supervisor') then
    raise exception 'only the owner or a supervisor voids'
      using errcode = '42501';
  end if;
  if new.target_type = 'payment' then
    select received_by into v_creator
    from public.payments where id = new.target_id;
    if not found then
      raise exception 'payment % is not in the cloud', new.target_id
        using errcode = '23503';
    end if;
    select array_agg(distinct stay_id) into v_stays
    from public.stay_charges where payment_id = new.target_id;
  elsif new.target_type = 'stay' then
    select checked_in_by into v_creator
    from public.stays where id = new.target_id;
    if not found then
      raise exception 'stay % is not in the cloud', new.target_id
        using errcode = '23503';
    end if;
    v_stays := array[new.target_id];
  else
    -- Refund payouts: the corrections book, not a void, for now.
    raise exception 'refund payouts are not voided' using errcode = '23514';
  end if;
  if v_creator = new.voided_by then
    raise exception 'nobody voids a record they created'
      using errcode = '42501';
  end if;
  -- The first upload sends refunds before voids; a payment voided while
  -- its guest was still in, who then left early with a refund, is valid in
  -- the order it happened, so the snapshot stands aside from this check.
  if not app_private.importing() and exists (
    select 1 from public.refunds
    where stay_id = any (coalesce(v_stays, '{}'::text[]))) then
    raise exception 'a stay with a refund is not voided'
      using errcode = '23514';
  end if;
  return new;
end $$;

create trigger voids_rules before insert on public.voids
  for each row execute function app_private.voids_rules();

-- ── 2. The desk says how many voids it holds ───────────────────────────

alter table public.desk_status
  add column voids_held integer not null default 0 check (voids_held >= 0);

drop function public.desk_heartbeat(integer, timestamptz, text, text, integer);
create function public.desk_heartbeat(
  p_pending integer, p_last_push_at timestamptz, p_problem text,
  p_app_version text, p_clock_offset integer default null,
  p_voids_held integer default 0
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_device text := app_private.require_desk();
begin
  insert into public.desk_status as s
    (device_id, reported_at, last_push_at, pending, problem, app_version,
     clock_offset_seconds, voids_held)
  values (v_device, now(), p_last_push_at, p_pending, p_problem, p_app_version,
    p_clock_offset, coalesce(p_voids_held, 0))
  on conflict (device_id) do update set
    reported_at = excluded.reported_at, last_push_at = excluded.last_push_at,
    pending = excluded.pending, problem = excluded.problem,
    app_version = excluded.app_version,
    clock_offset_seconds = excluded.clock_offset_seconds,
    voids_held = excluded.voids_held;
end $$;

revoke execute on function
  public.desk_heartbeat(integer, timestamptz, text, text, integer, integer)
  from public, anon;
grant execute on function
  public.desk_heartbeat(integer, timestamptz, text, text, integer, integer)
  to authenticated;
