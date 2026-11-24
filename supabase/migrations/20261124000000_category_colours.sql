-- v2 PR 4 (story/ui-4-category-colours): each room category has a colour
-- key, as on the desk (schema v12, `bed_categories.colour`). The desk is the
-- only writer of the colour: its `category.update` rows arrive through the
-- push like any other change. Nothing new is pulled.

alter table public.bed_categories
  add column colour text not null default 'slate'
    constraint bed_categories_colour_check
    check (colour in ('gold', 'violet', 'teal', 'slate', 'plum', 'bronze'));

-- The seeded categories get their colours by id, as the desk's v12
-- migration gives them (lib/core/database/category_colours.dart); any other
-- category keeps slate.
update public.bed_categories set colour = case id
    when '28a0fbdd-ed0b-4d51-80e0-90bf851fc142' then 'gold'    -- VIP
    when 'fb699568-46ad-4274-b28c-0d4f2545c5c6' then 'violet'  -- Deluxe
    when 'cdc98a60-8cb9-4791-a0a9-66c4493d132d' then 'teal'    -- Comfort
    else 'slate'                                               -- Normal
  end
where id in ('28a0fbdd-ed0b-4d51-80e0-90bf851fc142',
             'fb699568-46ad-4274-b28c-0d4f2545c5c6',
             'cdc98a60-8cb9-4791-a0a9-66c4493d132d',
             'ccf717df-8854-4ff5-b1f0-aec27d05147d');

-- Rows from a desk that hasn't upgraded yet (or queued in its outbox before
-- it did) have no colour key, and jsonb_populate_record gives NULL for a
-- missing key, not the default: NOT NULL would refuse them, and a refused
-- row stops the desk's queue. This trigger keeps the colour the row already
-- has in the cloud, or slate for a new one, before the constraints are
-- checked (BEFORE row triggers run first; for INSERT ... ON CONFLICT,
-- `excluded` carries what they set). Same pattern as
-- 20261110000100_cash_drawer_defaults.sql.
create function app_private.bed_categories_defaults() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.colour is null then
    if tg_op = 'UPDATE' then
      new.colour := old.colour;
    else
      select c.colour into new.colour
      from public.bed_categories c where c.id = new.id;
    end if;
  end if;
  new.colour := coalesce(new.colour, 'slate');
  return new;
end $$;
create trigger bed_categories_defaults
  before insert or update on public.bed_categories
  for each row execute function app_private.bed_categories_defaults();
