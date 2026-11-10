-- Story B1 fix (story/fd-11-b1-blind-close): defaults for rows that arrive
-- without the v10 columns.
--
-- The sync functions build each pushed row with jsonb_populate_record,
-- which gives NULL, not the column's default, for a key the row doesn't
-- have. Shift rows written before a desk's v10 upgrade (still queued in its
-- outbox, or from a desk not yet updated) have no needs_review, so
-- 20261110000000_cash_drawer's NOT NULL refused them, and a refused row
-- stops the desk's queue. These triggers fill the defaults before the
-- constraints are checked (BEFORE row triggers run first; for
-- INSERT ... ON CONFLICT, `excluded` carries what they set).

create function app_private.shifts_defaults() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.needs_review := coalesce(new.needs_review, false);
  return new;
end $$;
create trigger shifts_defaults before insert or update on public.shifts
  for each row execute function app_private.shifts_defaults();

create function app_private.drawer_events_defaults() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.removed := coalesce(new.removed, 0);
  new.needs_review := coalesce(new.needs_review, false);
  return new;
end $$;
create trigger drawer_events_defaults before insert on public.drawer_events
  for each row execute function app_private.drawer_events_defaults();
