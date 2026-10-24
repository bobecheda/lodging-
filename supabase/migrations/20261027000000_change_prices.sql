-- owner-app-2: the owner's price edits, from the desk or the phone, save
-- only if each category still has the price the owner started from, so an
-- edit made elsewhere is never silently overwritten. See docs/sync.md.

-- Where each category's price was last edited (desk or phone): the "where"
-- of a lost race. Approvals are found through price_decisions.
create table app_private.price_changes (
  category_id text primary key,
  device_id text not null,
  changed_at timestamptz not null
);
revoke all on app_private.price_changes from public, anon, authenticated;

-- p_changes: [{category_id, expected, price}]. All or nothing: every
-- category is checked before any is written. Answers
--   {status: 'changed'}
--   {status: 'stale', category_id, current_price, changed_at, changed_on}
--     (changed_on: 'desk', 'phone' or null when unknown)
--   {status: 'missing', category_id}
-- A retry of the same change (same device and time) answers 'changed'.
create function public.change_prices(
  p_changes jsonb, p_at timestamptz, p_device_id text, p_audit jsonb default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_item jsonb;
  v_category public.bed_categories;
  v_edit app_private.price_changes;
  v_device text;
  v_at timestamptz;
  v_retry boolean := true;
begin
  perform app_private.require_role('owner');
  perform pg_advisory_xact_lock(hashtext('lodging.owner_writes'));
  for v_item in select value from jsonb_array_elements(p_changes) loop
    select * into v_category from public.bed_categories
    where id = v_item ->> 'category_id';
    if not found then
      return jsonb_build_object('status', 'missing',
        'category_id', v_item ->> 'category_id');
    end if;
    select * into v_edit from app_private.price_changes
    where category_id = v_category.id;
    -- This same change already went in (the answer was lost).
    if v_category.price_per_night = (v_item ->> 'price')::integer
        and v_edit.device_id = p_device_id and v_edit.changed_at = p_at then
      continue;
    end if;
    v_retry := false;
    if v_category.price_per_night <> (v_item ->> 'expected')::integer then
      -- The latest of the last edit and the last approval says where.
      v_device := v_edit.device_id;
      v_at := v_edit.changed_at;
      select d.device_id, d.decided_at into v_device, v_at
      from public.price_decisions d
      join public.price_requests r on r.id = d.request_id
      where r.category_id = v_category.id and d.decision = 'approved'
        and (v_at is null or d.decided_at > v_at)
      order by d.decided_at desc limit 1;
      if not found then
        v_device := v_edit.device_id;
        v_at := v_edit.changed_at;
      end if;
      return jsonb_build_object(
        'status', 'stale',
        'category_id', v_category.id,
        'current_price', v_category.price_per_night,
        'changed_at', coalesce(v_category.price_updated_at, v_at,
          v_category.updated_at),
        'changed_on', case
          when v_device is null then null
          when exists (select 1 from app_private.devices
            where device_id = v_device) then 'desk'
          else 'phone' end);
    end if;
  end loop;
  if v_retry then
    return jsonb_build_object('status', 'changed');
  end if;
  for v_item in select value from jsonb_array_elements(p_changes) loop
    update public.bed_categories
    set price_per_night = (v_item ->> 'price')::integer, price_updated_at = p_at
    where id = v_item ->> 'category_id';
    insert into app_private.price_changes as c (category_id, device_id, changed_at)
    values (v_item ->> 'category_id', p_device_id, p_at)
    on conflict (category_id) do update
      set device_id = excluded.device_id, changed_at = excluded.changed_at;
  end loop;
  perform app_private.insert_audit(p_audit);
  return jsonb_build_object('status', 'changed');
end $$;

revoke execute on function public.change_prices(jsonb, timestamptz, text, jsonb)
  from public, anon;
grant execute on function public.change_prices(jsonb, timestamptz, text, jsonb)
  to authenticated;
