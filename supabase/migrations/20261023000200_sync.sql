-- Who may do what in the cloud, and the only ways in. See docs/sync.md.
--
-- Roles come from the sign-in token's app_metadata, set only by the
-- connect-desk Edge Function (service key):
--   role 'desk'  + device_id : a connected desk (one Supabase user per desk)
--   role 'owner' + user_id   : the owner (user_id = the owner's desk users.id)
-- Staff never sign in to the cloud.
--
-- Nobody writes a table directly: RLS is on everywhere with no write
-- policies, and every write goes through a SECURITY DEFINER function below
-- that checks the caller's role. Reads: the owner reads everything; nobody
-- else reads anything yet (the desk's pull comes with sync-2).

-- ── Connection records ─────────────────────────────────────────────────

create table app_private.devices (
  device_id text primary key,
  auth_user_id uuid not null unique,
  connected_at timestamptz not null default now(),
  first_upload_done_at timestamptz
);

-- One-time codes you create in the SQL editor (new_install_code below);
-- only a hash is kept.
create table app_private.install_codes (
  code_hash text primary key,
  created_at timestamptz not null default now(),
  used_at timestamptz,
  used_by_device text
);

-- The one owner account.
create table app_private.owner (
  singleton boolean primary key default true check (singleton),
  auth_user_id uuid not null unique,
  user_id text not null,
  email text not null
);

-- Each desk's latest heartbeat (every ~5 min, even while its queue is
-- stopped): what the owner's phone shows as "Desk last synced 3 h ago".
create table public.desk_status (
  device_id text primary key,
  reported_at timestamptz not null,
  last_push_at timestamptz,
  pending integer not null check (pending >= 0),
  problem text,
  app_version text
);

-- ── Token helpers ──────────────────────────────────────────────────────

create function app_private.jwt_role() returns text
language sql stable set search_path = '' as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
$$;

create function app_private.jwt_device() returns text
language sql stable set search_path = '' as $$
  select auth.jwt() -> 'app_metadata' ->> 'device_id'
$$;

create function app_private.jwt_user_id() returns text
language sql stable set search_path = '' as $$
  select auth.jwt() -> 'app_metadata' ->> 'user_id'
$$;

create function app_private.require_role(p_role text) returns void
language plpgsql stable set search_path = '' as $$
begin
  if app_private.jwt_role() <> p_role then
    raise exception 'only the % can do this', p_role using errcode = '42501';
  end if;
end $$;

-- The calling desk, connected; refuses anything else.
create function app_private.require_desk() returns text
language plpgsql stable set search_path = '' as $$
declare v_device text := app_private.jwt_device();
begin
  perform app_private.require_role('desk');
  if v_device is null or not exists (
    select 1 from app_private.devices d
    join auth.users u on u.id = d.auth_user_id
    where d.device_id = v_device and u.id = auth.uid()) then
    raise exception 'this desk is not connected' using errcode = '42501';
  end if;
  return v_device;
end $$;

-- ── Writing rows ───────────────────────────────────────────────────────

create function app_private.synced_tables() returns text[]
language sql immutable as $$
  select array[
    'users', 'settings', 'bed_categories', 'rooms', 'beds', 'housekeepers',
    'guests', 'shifts', 'stays', 'payments', 'stay_charges', 'refunds',
    'refund_decisions', 'price_requests', 'price_decisions',
    'housekeeping_tasks', 'inventory_items', 'inventory_movements', 'voids',
    'expenses', 'audit_log']
$$;

-- Written by the owner's path only: decisions (and, column-wise, prices).
create function app_private.owner_tables() returns text[]
language sql immutable as $$
  select array['refund_decisions', 'price_decisions']
$$;

-- Upserts one row by its primary key. A row already there changes only
-- when the incoming updated_at is newer, so a re-sent batch is a no-op.
-- audit_log and decisions are insert-if-absent. bed_categories never take
-- price_per_night from an update: the price is the owner's (set_prices,
-- decide_price_request); a new category keeps its first price.
create function app_private.upsert_row(p_table text, p_row jsonb) returns void
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
  select string_agg(format('%I = excluded.%I', c.column_name, c.column_name), ', ')
    into v_set
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = p_table
    and c.column_name not in ('server_seq', 'price_updated_at', 'created_at', v_pk)
    and not (p_table = 'bed_categories' and c.column_name = 'price_per_night');
  if p_table = 'audit_log' or p_table = any (app_private.owner_tables()) then
    execute format(
      'insert into public.%1$I (%2$s) select %2$s '
      'from jsonb_populate_record(null::public.%1$I, $1) '
      'on conflict (%3$I) do nothing',
      p_table, v_cols, v_pk) using p_row;
  else
    execute format(
      'insert into public.%1$I as t (%2$s) select %2$s '
      'from jsonb_populate_record(null::public.%1$I, $1) '
      'on conflict (%3$I) do update set %4$s '
      'where excluded.updated_at > t.updated_at',
      p_table, v_cols, v_pk, v_set) using p_row;
  end if;
end $$;

-- Applies [{table, row}, ...] in order, all or nothing. A refused row names
-- itself: the message has the table and id, DETAIL its index in the batch.
create function app_private.apply_rows(p_rows jsonb, p_allowed text[]) returns integer
language plpgsql set search_path = '' as $$
declare
  v_item jsonb;
  v_index integer := 0;
  v_table text;
begin
  for v_item in select value from jsonb_array_elements(p_rows) loop
    v_table := v_item ->> 'table';
    begin
      if not v_table = any (p_allowed) then
        raise exception 'this sign-in can''t write %', v_table using errcode = '42501';
      end if;
      perform app_private.upsert_row(v_table, v_item -> 'row');
    exception when others then
      raise exception '% %: %', v_table,
        coalesce(v_item -> 'row' ->> 'id', v_item -> 'row' ->> 'key'), sqlerrm
        using errcode = sqlstate, detail = v_index::text;
    end;
    v_index := v_index + 1;
  end loop;
  return v_index;
end $$;

-- ── The desk ───────────────────────────────────────────────────────────

-- The desk's outbox, in order, once its first upload is finished. Only its
-- own rows (device_id), never the owner's tables.
create function public.push_changes(p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_device text := app_private.require_desk();
  v_desk_tables text[];
begin
  if not exists (
    select 1 from app_private.devices
    where device_id = v_device and first_upload_done_at is not null) then
    raise exception 'the first upload is not finished' using errcode = '55000';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_rows) r
    where r.value -> 'row' ->> 'device_id' is distinct from v_device) then
    raise exception 'a desk pushes only its own rows' using errcode = '42501';
  end if;
  select array_agg(t) into v_desk_tables
  from unnest(app_private.synced_tables()) t
  where not t = any (app_private.owner_tables());
  return app_private.apply_rows(p_rows, v_desk_tables);
end $$;

-- The first upload, desk part: a snapshot of the desk's own tables in their
-- final state, resumable (batches may repeat). Only before the upload is
-- finished.
create function public.import_desk_rows(p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_device text := app_private.require_desk();
  v_desk_tables text[];
begin
  if exists (
    select 1 from app_private.devices
    where device_id = v_device and first_upload_done_at is not null) then
    raise exception 'the first upload is already finished' using errcode = '55000';
  end if;
  perform set_config('app.importing', 'on', true);
  select array_agg(t) into v_desk_tables
  from unnest(app_private.synced_tables()) t
  where not t = any (app_private.owner_tables());
  return app_private.apply_rows(p_rows, v_desk_tables);
end $$;

-- Whether this desk's first upload is finished (asked on start).
create function public.first_upload_done() returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_device text := app_private.require_desk();
begin
  return exists (
    select 1 from app_private.devices
    where device_id = v_device and first_upload_done_at is not null);
end $$;

-- Withdraws a waiting price request, first come first served against the
-- owner's decision (BR-2). Closing a category calls it too.
create function public.withdraw_price_request(
  p_request_id text, p_by text, p_reason text, p_at timestamptz
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_device text := app_private.require_desk();
  v_request public.price_requests;
  v_decision public.price_decisions;
begin
  perform pg_advisory_xact_lock(hashtext('lodging.owner_writes'));
  select * into v_request from public.price_requests where id = p_request_id;
  if not found then
    return jsonb_build_object('status', 'missing');
  end if;
  select * into v_decision from public.price_decisions where request_id = p_request_id;
  if found then
    return jsonb_build_object(
      'status', 'already_decided',
      'decision', v_decision.decision,
      'decided_at', v_decision.decided_at,
      'decided_by_name',
        (select full_name from public.users where id = v_decision.decided_by));
  end if;
  if v_request.withdrawn_at is not null then
    -- A retry of the same withdrawal succeeded already.
    return jsonb_build_object('status',
      case when v_request.withdrawn_at = p_at and v_request.withdrawn_by = p_by
        then 'withdrawn' else 'already_withdrawn' end);
  end if;
  update public.price_requests
  set withdrawn_at = p_at, withdrawn_by = p_by, withdraw_reason = p_reason,
      updated_at = p_at, device_id = v_device
  where id = p_request_id;
  return jsonb_build_object('status', 'withdrawn');
end $$;

-- Every ~5 minutes, whatever the queue is doing.
create function public.desk_heartbeat(
  p_pending integer, p_last_push_at timestamptz, p_problem text, p_app_version text
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_device text := app_private.require_desk();
begin
  insert into public.desk_status as s
    (device_id, reported_at, last_push_at, pending, problem, app_version)
  values (v_device, now(), p_last_push_at, p_pending, p_problem, p_app_version)
  on conflict (device_id) do update set
    reported_at = excluded.reported_at, last_push_at = excluded.last_push_at,
    pending = excluded.pending, problem = excluded.problem,
    app_version = excluded.app_version;
end $$;

-- ── The owner ──────────────────────────────────────────────────────────

-- The first upload, owner part: the decisions written on the desk before it
-- was connected, insert-if-absent.
create function public.import_owner_rows(p_device_id text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.require_role('owner');
  if not exists (
    select 1 from app_private.devices
    where device_id = p_device_id and first_upload_done_at is null) then
    raise exception 'no first upload is waiting for this desk' using errcode = '55000';
  end if;
  perform set_config('app.importing', 'on', true);
  return app_private.apply_rows(p_rows, app_private.owner_tables());
end $$;

create function public.finish_first_upload(p_device_id text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.require_role('owner');
  update app_private.devices set first_upload_done_at = now()
  where device_id = p_device_id and first_upload_done_at is null;
end $$;

-- Sets category prices ({category_id: price}); the price column is the
-- owner's. Idempotent.
create function public.set_prices(p_prices jsonb, p_at timestamptz) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_item record;
  v_count integer := 0;
begin
  perform app_private.require_role('owner');
  perform pg_advisory_xact_lock(hashtext('lodging.owner_writes'));
  for v_item in select key, value from jsonb_each(p_prices) loop
    update public.bed_categories
    set price_per_night = (v_item.value)::text::integer, price_updated_at = p_at
    where id = v_item.key;
    if not found then
      raise exception 'category % is not in the cloud yet', v_item.key
        using errcode = 'P0002';
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- Optional audit rows from the caller (the phone has no desk to push them);
-- the desk pushes its own through push_changes instead.
create function app_private.insert_audit(p_audit jsonb) returns void
language plpgsql set search_path = '' as $$
declare v_row jsonb;
begin
  for v_row in select value from jsonb_array_elements(coalesce(p_audit, '[]'::jsonb)) loop
    perform app_private.upsert_row('audit_log', v_row);
  end loop;
end $$;

-- Approves or rejects a refund, first decision wins (BR-8a). A retry of the
-- same decision (same id) answers 'decided' again.
create function public.decide_refund(
  p_id text, p_refund_id text, p_decision text, p_note text,
  p_at timestamptz, p_device_id text, p_audit jsonb default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_owner text := app_private.jwt_user_id();
  v_refund public.refunds;
  v_existing public.refund_decisions;
begin
  perform app_private.require_role('owner');
  perform pg_advisory_xact_lock(hashtext('lodging.owner_writes'));
  select * into v_existing from public.refund_decisions where refund_id = p_refund_id;
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
  select * into v_refund from public.refunds where id = p_refund_id;
  if not found then
    return jsonb_build_object('status', 'missing');
  end if;
  if p_decision = 'approved' and v_refund.requested_by = v_owner then
    raise exception 'nobody approves a refund they requested' using errcode = '42501';
  end if;
  insert into public.refund_decisions
    (id, created_at, updated_at, device_id, refund_id, decision, note, decided_by, decided_at)
  values (p_id, p_at, p_at, p_device_id, p_refund_id, p_decision,
    nullif(trim(p_note), ''), v_owner, p_at);
  perform app_private.insert_audit(p_audit);
  return jsonb_build_object('status', 'decided');
end $$;

-- Approves (and sets the price) or rejects a price request, first decision
-- wins; refused once withdrawn or once the price has moved on (BR-2).
create function public.decide_price_request(
  p_id text, p_request_id text, p_decision text, p_note text,
  p_at timestamptz, p_device_id text, p_audit jsonb default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_owner text := app_private.jwt_user_id();
  v_request public.price_requests;
  v_existing public.price_decisions;
  v_price integer;
begin
  perform app_private.require_role('owner');
  perform pg_advisory_xact_lock(hashtext('lodging.owner_writes'));
  select * into v_existing from public.price_decisions where request_id = p_request_id;
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
  select * into v_request from public.price_requests where id = p_request_id;
  if not found then
    return jsonb_build_object('status', 'missing');
  end if;
  if v_request.withdrawn_at is not null then
    return jsonb_build_object('status', 'withdrawn');
  end if;
  if p_decision = 'approved' then
    select price_per_night into v_price
    from public.bed_categories where id = v_request.category_id;
    if v_price <> v_request.old_price then
      return jsonb_build_object('status', 'stale', 'current_price', v_price);
    end if;
  end if;
  insert into public.price_decisions
    (id, created_at, updated_at, device_id, request_id, decision, note, decided_by, decided_at)
  values (p_id, p_at, p_at, p_device_id, p_request_id, p_decision,
    nullif(trim(p_note), ''), v_owner, p_at);
  if p_decision = 'approved' then
    update public.bed_categories
    set price_per_night = v_request.new_price, price_updated_at = p_at
    where id = v_request.category_id;
  end if;
  perform app_private.insert_audit(p_audit);
  return jsonb_build_object('status', 'decided');
end $$;

-- ── Connecting (service key only: the connect-desk Edge Function) ──────

-- Run in the SQL editor: returns a new one-time install code, once.
create function app_private.new_install_code() returns text
language plpgsql set search_path = '' as $$
declare
  v_alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_bytes bytea := extensions.gen_random_bytes(12);
  v_code text := '';
begin
  for i in 0..11 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
    if i in (3, 7) then v_code := v_code || '-'; end if;
  end loop;
  insert into app_private.install_codes (code_hash)
  values (encode(extensions.digest(v_code, 'sha256'), 'hex'));
  return v_code;
end $$;

create function public.install_code_unused(p_code text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app_private.install_codes
    where code_hash = encode(extensions.digest(upper(trim(p_code)), 'sha256'), 'hex')
      and used_at is null)
$$;

-- The owner account, if one exists: {auth_user_id, user_id, email}.
create function public.cloud_owner() returns jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(o) - 'singleton' from app_private.owner o
$$;

-- Records a connected desk (and the owner, the first time) and uses up the
-- install code, in one transaction.
create function public.register_desk(
  p_code text, p_device_id text, p_device_auth_id uuid,
  p_owner_auth_id uuid, p_owner_user_id text, p_owner_email text
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update app_private.install_codes
  set used_at = now(), used_by_device = p_device_id
  where code_hash = encode(extensions.digest(upper(trim(p_code)), 'sha256'), 'hex')
    and used_at is null;
  if not found then
    raise exception 'install code not valid or already used' using errcode = '42501';
  end if;
  insert into app_private.owner (auth_user_id, user_id, email)
  values (p_owner_auth_id, p_owner_user_id, p_owner_email)
  on conflict (singleton) do nothing;
  if not exists (
    select 1 from app_private.owner where auth_user_id = p_owner_auth_id) then
    raise exception 'this lodging already has another owner account' using errcode = '42501';
  end if;
  insert into app_private.devices (device_id, auth_user_id)
  values (p_device_id, p_device_auth_id)
  on conflict (device_id) do update set auth_user_id = excluded.auth_user_id;
end $$;

-- The desk's Supabase user, for "Reconnect this desk".
create function public.desk_auth_user(p_device_id text) returns uuid
language sql stable security definer set search_path = '' as $$
  select auth_user_id from app_private.devices where device_id = p_device_id
$$;

-- ── Security ───────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array app_private.synced_tables() || array['desk_status'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    -- The owner reads everything, guests' phones and IDs included (Data
    -- Protection Act: nobody else can read them in the cloud).
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using ((select app_private.jwt_role()) = ''owner'')',
      t || '_owner_reads', t);
  end loop;
end $$;

grant usage on schema app_private to authenticated;
revoke all on all functions in schema app_private from public, anon;
grant execute on function app_private.jwt_role() to authenticated;

revoke all on sequence public.sync_seq from anon, authenticated;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.push_changes(jsonb),
  public.import_desk_rows(jsonb),
  public.first_upload_done(),
  public.withdraw_price_request(text, text, text, timestamptz),
  public.desk_heartbeat(integer, timestamptz, text, text),
  public.import_owner_rows(text, jsonb),
  public.finish_first_upload(text),
  public.set_prices(jsonb, timestamptz),
  public.decide_refund(text, text, text, text, timestamptz, text, jsonb),
  public.decide_price_request(text, text, text, text, timestamptz, text, jsonb)
to authenticated;
grant execute on function
  public.install_code_unused(text),
  public.cloud_owner(),
  public.register_desk(text, text, uuid, uuid, text, text),
  public.desk_auth_user(text)
to service_role;
