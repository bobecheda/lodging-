-- v2 PR 4 (20261124000000_category_colours.sql): a colour key on each room
-- category, filled in for rows from a desk that hasn't upgraded. Run by
-- `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- ── Fixtures (as postgres) ─────────────────────────────────────────────

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000e1', 'dev-1@desk.lodging.invalid',
   'authenticated', 'authenticated');
insert into app_private.devices (device_id, auth_user_id, first_upload_done_at)
values ('dev-1', '00000000-0000-0000-0000-0000000000e1', now());

create schema tests_cc;
grant usage on schema tests_cc to anon, authenticated;

create function tests_cc.as_desk() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated",'
    '"app_metadata":{"role":"desk","device_id":"dev-1"}}', true);
  perform set_config('role', 'authenticated', true);
end $$;

-- A category as the desk sends it, with [p_extra] on top; [p_updated] is
-- its updated_at.
create function tests_cc.push(
  p_id text, p_name text, p_updated text, p_extra jsonb default '{}'
) returns integer language sql as $$
  select public.push_changes(jsonb_build_array(jsonb_build_object(
    'table', 'bed_categories',
    'row', jsonb_build_object('id', p_id, 'name', p_name,
      'price_per_night', 900, 'sort_order', 5, 'is_active', true,
      'created_at', '2026-11-24T09:00:00Z', 'updated_at', p_updated,
      'device_id', 'dev-1') || p_extra)))
$$;

-- ── The column ─────────────────────────────────────────────────────────

select col_not_null('public', 'bed_categories', 'colour', 'colour is required');
select col_default_is('public', 'bed_categories', 'colour', 'slate',
  'slate by default');

-- ── Pushed rows ────────────────────────────────────────────────────────

select tests_cc.as_desk();
select lives_ok($$select tests_cc.push('c-family', 'Family',
  '2026-11-24T09:00:00Z', '{"colour":"plum"}')$$,
  'an upgraded desk sends its colour');
select lives_ok($$select tests_cc.push('c-suite', 'Suite',
  '2026-11-24T09:00:00Z')$$,
  'an older desk''s new category, with no colour key, is not refused');
select lives_ok($$select tests_cc.push('c-family', 'Family',
  '2026-11-24T10:00:00Z')$$,
  'an older desk''s later change, with no colour key, is not refused');
select throws_ok($$select tests_cc.push('c-odd', 'Odd',
  '2026-11-24T09:00:00Z', '{"colour":"pink"}')$$,
  '23514', null, 'only palette keys');
reset role;

select is((select colour from public.bed_categories where id = 'c-suite'),
  'slate', 'a new category without a colour is slate');
select is((select colour from public.bed_categories where id = 'c-family'),
  'plum', 'a change without a colour keeps the colour it had');

-- The owner's price change (change_prices) leaves the colour alone.
update public.bed_categories set price_per_night = 950,
  updated_at = '2026-11-24T11:00:00Z' where id = 'c-family';
select is((select colour from public.bed_categories where id = 'c-family'),
  'plum', 'an update that doesn''t name the colour keeps it');

select * from finish();
