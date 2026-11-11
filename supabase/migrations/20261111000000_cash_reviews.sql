-- Story B3 (story/fd-11-b3-cash-review): reviewing the drawer's gaps.
-- Timestamped after B2's 20261110000200_drawer_counts.
--
-- A shift close or a drawer count recorded with needs_review is approved
-- or rejected once, in the cloud first (decide_cash_review), and pulled by
-- the desk (pull_changes → cash_reviews). The desk checks the same rules
-- first (lib/features/shifts/domain/cash_review.dart):
-- - the decider is the owner or a supervisor, active; never a receptionist;
-- - nobody decides an item that names them (shift user or closer; a
--   count's counter or the one present);
-- - an item naming a supervisor is the owner's only;
-- - the owner decides the gaps from the owner's own counts;
-- - a rejection needs a reason; decided once (first decision wins).
-- The owner decides with their own sign-in. A supervisor decides on the
-- desk, which calls with its device sign-in and names them: the desk can
-- only ever decide for a supervisor, so it can't decide a supervisor's
-- item on its own.

-- ── 1. The table ───────────────────────────────────────────────────────

create table public.cash_reviews (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  target_type text not null check (target_type in ('shift', 'drawer_event')),
  target_id text not null,
  decision text not null check (decision in ('approved', 'rejected')),
  reason text check (length(reason) <= 200),
  decided_by text not null references public.users (id),
  decided_at timestamptz not null,
  server_seq bigint not null default nextval('public.sync_seq'),
  unique (target_type, target_id),
  check (decision = 'approved' or length(trim(coalesce(reason, ''))) > 0)
);

create trigger cash_reviews_no_delete before delete on public.cash_reviews
  for each row execute function app_private.refuse('cash_reviews rows are never deleted');
create trigger cash_reviews_no_update before update on public.cash_reviews
  for each row execute function app_private.refuse('cash_reviews rows are never edited');

alter table public.cash_reviews enable row level security;
revoke all on public.cash_reviews from anon, authenticated;
grant select on public.cash_reviews to authenticated;
create policy cash_reviews_owner_reads on public.cash_reviews
  for select to authenticated
  using ((select app_private.jwt_role()) = 'owner');

-- ── 2. Sync: a decision table, written in the cloud first ──────────────

create or replace function app_private.synced_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array[
    'users', 'settings', 'bed_categories', 'rooms', 'beds', 'housekeepers',
    'guests', 'shifts', 'drawer_events', 'stays', 'payments', 'stay_charges',
    'refunds', 'refund_decisions', 'price_requests', 'price_decisions',
    'cash_reviews', 'housekeeping_tasks', 'inventory_items',
    'inventory_movements', 'voids', 'expenses', 'audit_log']
$$;

-- Not pushed by a desk (push_changes refuses these tables); the first
-- upload sends earlier ones with the owner's sign-in.
create or replace function app_private.owner_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array['refund_decisions', 'price_decisions', 'cash_reviews']
$$;

-- ── 3. The decision ────────────────────────────────────────────────────

create function public.decide_cash_review(
  p_id text, p_target_type text, p_target_id text, p_decision text,
  p_reason text, p_decided_by text, p_at timestamptz, p_device_id text,
  p_audit jsonb default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_caller text := app_private.jwt_role();
  v_decider text;
  v_decider_role text;
  v_existing public.cash_reviews;
  v_needs boolean;
  v_named text[];
  v_counter_role text;
begin
  if v_caller = 'owner' then
    v_decider := app_private.jwt_user_id();
  elsif v_caller = 'desk' then
    perform app_private.require_desk();
    v_decider := p_decided_by;
  else
    raise exception 'only the owner or a desk decides a review'
      using errcode = '42501';
  end if;
  select role into v_decider_role from public.users
  where id = v_decider and is_active;
  if v_decider_role is null or v_decider_role not in ('owner', 'supervisor') then
    raise exception 'only the owner or a supervisor reviews cash'
      using errcode = '42501';
  end if;
  if v_caller = 'desk' and v_decider_role <> 'supervisor' then
    raise exception 'a desk decides only for a supervisor'
      using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'a decision is approved or rejected' using errcode = '22023';
  end if;
  if p_decision = 'rejected' and (length(trim(coalesce(p_reason, ''))) = 0
      or length(trim(p_reason)) > 200) then
    raise exception 'a rejection needs a reason of at most 200 characters'
      using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(hashtext('lodging.owner_writes'));
  select * into v_existing from public.cash_reviews
  where target_type = p_target_type and target_id = p_target_id;
  if found then
    if v_existing.id = p_id then
      return jsonb_build_object('status', 'decided');
    end if;
    return jsonb_build_object(
      'status', 'already_decided',
      'decision', v_existing.decision,
      'decided_at', v_existing.decided_at,
      'decided_by_name',
        (select full_name from public.users where id = v_existing.decided_by),
      'row', to_jsonb(v_existing) - 'server_seq');
  end if;

  if p_target_type = 'shift' then
    select s.needs_review, array_remove(array[s.user_id, s.closed_by], null)
      into v_needs, v_named
    from public.shifts s where s.id = p_target_id and s.status = 'closed';
  elsif p_target_type = 'drawer_event' then
    select d.needs_review,
      array_remove(array[d.counted_by, d.present_user], null),
      (select role from public.users where id = d.counted_by)
      into v_needs, v_named, v_counter_role
    from public.drawer_events d where d.id = p_target_id;
  else
    raise exception 'unknown review target %', p_target_type
      using errcode = '22023';
  end if;
  if v_needs is null then
    return jsonb_build_object('status', 'missing');
  end if;
  if not v_needs then
    raise exception 'nothing to review here' using errcode = '23514';
  end if;

  if v_counter_role = 'owner' then
    if v_decider_role <> 'owner' then
      raise exception 'the owner decides gaps from the owner''s own counts'
        using errcode = '42501';
    end if;
  else
    if v_decider = any (v_named) then
      raise exception 'nobody decides an item that names them'
        using errcode = '42501';
    end if;
    if v_decider_role <> 'owner' and exists (
      select 1 from public.users
      where id = any (v_named) and role in ('owner', 'supervisor')) then
      raise exception 'a supervisor''s item is the owner''s to decide'
        using errcode = '42501';
    end if;
  end if;

  insert into public.cash_reviews (id, created_at, updated_at, device_id,
    target_type, target_id, decision, reason, decided_by, decided_at)
  values (p_id, p_at, p_at, p_device_id, p_target_type, p_target_id,
    p_decision, nullif(trim(p_reason), ''), v_decider, p_at);
  perform app_private.insert_audit(p_audit);
  return jsonb_build_object('status', 'decided');
end $$;

revoke execute on function public.decide_cash_review(text, text, text, text,
  text, text, timestamptz, text, jsonb) from public, anon;
grant execute on function public.decide_cash_review(text, text, text, text,
  text, text, timestamptz, text, jsonb) to authenticated;

-- ── 4. The desk pulls them ─────────────────────────────────────────────

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
    select 'cash_reviews', r.server_seq, to_jsonb(r) - 'server_seq'
    from public.cash_reviews r where r.server_seq > p_after
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
