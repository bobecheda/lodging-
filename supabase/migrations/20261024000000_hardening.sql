-- Cloud hardening after the Supabase review (story/cloud-hardening).
-- Applied migrations are never edited; this one replaces what changes.

-- ── 1. Rows that never change once in the cloud ────────────────────────
-- audit_log, decisions, stay_charges and voids are insert-only. payments are
-- too, except print_count (reprints say COPY), which only ever goes up:
-- amount, method, M-Pesa code, shift and the created fields never change
-- after the first insert, whatever updated_at says.

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
  if p_table in ('audit_log', 'stay_charges', 'voids')
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

-- ── 2. Install codes expire after 7 days ───────────────────────────────

alter table app_private.install_codes
  add column expires_at timestamptz not null default now() + interval '7 days';

-- Returns "7KQ2-M9XD-4HPA · expires Fri 30 Oct 2026, 14:05 (Nairobi)", once.
create or replace function app_private.new_install_code() returns text
language plpgsql set search_path = '' as $$
declare
  v_alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_bytes bytea := extensions.gen_random_bytes(12);
  v_code text := '';
  v_expires timestamptz;
begin
  for i in 0..11 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
    if i in (3, 7) then v_code := v_code || '-'; end if;
  end loop;
  insert into app_private.install_codes (code_hash)
  values (encode(extensions.digest(v_code, 'sha256'), 'hex'))
  returning expires_at into v_expires;
  return v_code || ' · expires '
    || to_char(v_expires at time zone 'Africa/Nairobi', 'Dy FMDD Mon YYYY, HH24:MI')
    || ' (Nairobi)';
end $$;

create or replace function public.install_code_unused(p_code text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app_private.install_codes
    where code_hash = encode(extensions.digest(upper(trim(p_code)), 'sha256'), 'hex')
      and used_at is null and expires_at > now())
$$;

create or replace function public.register_desk(
  p_code text, p_device_id text, p_device_auth_id uuid,
  p_owner_auth_id uuid, p_owner_user_id text, p_owner_email text
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update app_private.install_codes
  set used_at = now(), used_by_device = p_device_id
  where code_hash = encode(extensions.digest(upper(trim(p_code)), 'sha256'), 'hex')
    and used_at is null and expires_at > now();
  if not found then
    raise exception 'install code not valid, expired or already used'
      using errcode = '42501';
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

-- ── 3. connect-desk: at most 10 failed tries an hour per owner email ───

create table app_private.connect_attempts (
  email text not null,
  at timestamptz not null default now(),
  ok boolean not null
);
create index connect_attempts_email_at on app_private.connect_attempts (email, at);

-- Fewer than 10 failed attempts for [p_email] in the last hour.
create function public.connect_attempt_allowed(p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select count(*) < 10 from app_private.connect_attempts
  where email = lower(trim(p_email)) and not ok and at > now() - interval '1 hour'
$$;

create function public.record_connect_attempt(p_email text, p_ok boolean) returns void
language sql security definer set search_path = '' as $$
  insert into app_private.connect_attempts (email, ok) values (lower(trim(p_email)), p_ok)
$$;

revoke execute on function
  public.connect_attempt_allowed(text),
  public.record_connect_attempt(text, boolean)
from public, anon, authenticated;
grant execute on function
  public.connect_attempt_allowed(text),
  public.record_connect_attempt(text, boolean)
to service_role;

-- ── 6. Fixed search paths ──────────────────────────────────────────────

alter function app_private.synced_tables() set search_path = '';
alter function app_private.owner_tables() set search_path = '';
