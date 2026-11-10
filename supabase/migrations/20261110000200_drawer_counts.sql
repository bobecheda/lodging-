-- Story B2 (story/fd-11-b2-drawer-check): drawer checks and weekly
-- collections. Timestamped after B1's 20261110000100_cash_drawer_defaults.
--
-- The desk writes them (lib/features/shifts/data/drawer_repository.dart)
-- after applying these same rules, and pushes them insert-only. If the
-- cloud still refuses one, the desk holds that row aside and pushes
-- everything after it (it never stops the queue; docs/sync.md).
--
-- A check or collection is counted by the owner or a supervisor with
-- someone from the desk present (a supervisor or receptionist, never the
-- counter), who co-signed with their own password; with a shift open, it is
-- that shift's user. A first count is always kept; a count that needs
-- review has its reason. Roles are judged from public.users, which the desk
-- pushes first, in order (as for voids).

create or replace function app_private.drawer_events_rules() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_role text;
  v_present_role text;
  v_shift_user text;
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
  if new.kind = 'start' then
    if exists (
      select 1 from public.drawer_events
      where device_id = new.device_id and kind = 'start') then
      raise exception 'the starting cash was already counted'
        using errcode = '23514';
    end if;
    return new;
  end if;
  -- A check or a collection.
  select role into v_present_role from public.users where id = new.present_user;
  if v_present_role is null
    or v_present_role not in ('supervisor', 'receptionist') then
    raise exception 'someone from the desk must be present'
      using errcode = '23514';
  end if;
  if new.shift_id is not null then
    select user_id into v_shift_user from public.shifts where id = new.shift_id;
    if v_shift_user is distinct from new.present_user then
      raise exception 'the receptionist on shift must be the one present'
        using errcode = '23514';
    end if;
  end if;
  if new.first_count is null or new.first_count < 0 then
    raise exception 'a drawer count keeps its first count'
      using errcode = '23514';
  end if;
  if new.needs_review and length(trim(coalesce(new.note, ''))) = 0 then
    raise exception 'a count that needs review needs its reason'
      using errcode = '23514';
  end if;
  return new;
end $$;
