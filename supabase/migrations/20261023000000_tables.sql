-- lodging_pos cloud schema: the desk's synced drift tables (schema v8),
-- mirrored with the same CHECK and UNIQUE rules. See docs/sync.md.
--
-- Differences from the desk, all deliberate:
-- * Times are timestamptz and flags boolean (the desk stores ISO text and
--   0/1); ids stay text UUIDs, as on the desk.
-- * COLLATE NOCASE uniqueness becomes a unique index on lower()/upper().
-- * users has no password_hash: staff logins stay on the desk.
-- * Every table has server_seq, set from one sequence on every insert and
--   update: the pull cursor (sync-2), never a device clock.
-- * bed_categories.price_updated_at: when the owner's path last set the
--   price (the price column belongs to the owner, see 0100_functions).

-- Helpers that must never be callable through the API.
create schema app_private;
revoke all on schema app_private from public;

create sequence public.sync_seq;

-- ── Setup ──────────────────────────────────────────────────────────────

create table public.users (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  full_name text not null,
  username text not null unique check (username = lower(trim(username))),
  role text not null check (role in ('owner', 'supervisor', 'receptionist')),
  is_active boolean not null default true,
  must_change_password boolean not null,
  server_seq bigint not null default nextval('public.sync_seq')
);

create table public.settings (
  key text primary key,
  value text not null,
  updated_by text references public.users (id),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  server_seq bigint not null default nextval('public.sync_seq')
);

create table public.bed_categories (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  name text not null check (name = trim(name) and length(name) between 1 and 30),
  price_per_night integer not null check (price_per_night between 1 and 100000),
  sort_order integer not null,
  is_active boolean not null default true,
  price_updated_at timestamptz,
  server_seq bigint not null default nextval('public.sync_seq')
);
create unique index bed_categories_name_nocase on public.bed_categories (lower(name));

create table public.rooms (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  room_number text not null unique check (room_number = upper(trim(room_number))),
  floor text,
  notes text,
  is_active boolean not null default true,
  server_seq bigint not null default nextval('public.sync_seq')
);

create table public.beds (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  room_id text not null references public.rooms (id),
  label text not null check (label in ('A', 'B')),
  category_id text not null references public.bed_categories (id),
  cleanliness text not null check (cleanliness in ('clean', 'not_cleaned')),
  is_active boolean not null default true,
  server_seq bigint not null default nextval('public.sync_seq'),
  unique (room_id, label)
);

create table public.housekeepers (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  full_name text not null,
  phone text,
  is_active boolean not null default true,
  server_seq bigint not null default nextval('public.sync_seq')
);

-- ── Front desk ─────────────────────────────────────────────────────────

create table public.guests (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  full_name text not null,
  phone text not null,
  id_type text check (id_type in ('national_id', 'passport', 'alien_id')),
  id_number text,
  server_seq bigint not null default nextval('public.sync_seq'),
  check (id_number is null or id_type is not null)
);
create index guests_phone on public.guests (lower(phone));
create index guests_id_number on public.guests (lower(id_number));
create unique index guests_id_unique on public.guests (id_type, lower(id_number))
  where id_number is not null;

create table public.shifts (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  user_id text not null references public.users (id),
  opened_at timestamptz not null,
  opening_float integer not null check (opening_float >= 0),
  closed_at timestamptz,
  expected_cash integer,
  expected_paybill integer,
  counted_cash integer,
  variance integer,
  status text not null check (status in ('open', 'closed')),
  first_count integer,
  close_note text check (length(close_note) <= 200),
  closed_by text references public.users (id),
  server_seq bigint not null default nextval('public.sync_seq'),
  check ((status = 'open') = (closed_at is null)),
  check (status = 'open' or (expected_cash is not null and expected_paybill is not null
    and counted_cash is not null and variance is not null
    and variance = counted_cash - expected_cash)),
  check ((status = 'open') = (closed_by is null)),
  check ((status = 'open') = (first_count is null))
);
create unique index shifts_one_open_per_device on public.shifts (device_id)
  where status = 'open';

create table public.stays (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  guest_id text not null references public.guests (id),
  bed_id text not null references public.beds (id),
  check_in_at timestamptz not null,
  paid_until timestamptz not null,
  checked_out_at timestamptz,
  status text not null check (status in ('active', 'closed')),
  checked_in_by text not null references public.users (id),
  checked_out_by text references public.users (id),
  room_number text not null,
  bed_label text not null check (bed_label in ('A', 'B')),
  server_seq bigint not null default nextval('public.sync_seq'),
  check ((status = 'active') = (checked_out_at is null)),
  check ((status = 'active') = (checked_out_by is null))
);
create index stays_guest on public.stays (guest_id);
create unique index stays_one_active_per_bed on public.stays (bed_id)
  where status = 'active';

create table public.payments (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  receipt_number text not null unique,
  shift_id text not null references public.shifts (id),
  received_by text not null references public.users (id),
  received_at timestamptz not null,
  amount integer not null check (amount > 0),
  method text not null check (method in ('cash', 'paybill')),
  mpesa_code text,
  print_count integer not null default 0,
  server_seq bigint not null default nextval('public.sync_seq'),
  check ((method = 'paybill') = (mpesa_code is not null))
);
create unique index payments_mpesa_code_nocase on public.payments (upper(mpesa_code));
create index payments_shift on public.payments (shift_id);

create table public.stay_charges (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  stay_id text not null references public.stays (id),
  payment_id text not null references public.payments (id),
  kind text not null check (kind in ('check_in', 'extension', 'late_checkout')),
  nights integer not null check (nights >= 1),
  price_per_night integer not null check (price_per_night > 0),
  amount integer not null,
  period_start timestamptz not null,
  period_end timestamptz not null,
  category_id text not null references public.bed_categories (id),
  category_name text not null,
  server_seq bigint not null default nextval('public.sync_seq'),
  check (amount = nights * price_per_night),
  check (period_end > period_start)
);
create index stay_charges_stay on public.stay_charges (stay_id);
create index stay_charges_payment on public.stay_charges (payment_id);

create table public.refunds (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  stay_id text not null unique references public.stays (id),
  nights integer not null check (nights >= 1),
  price_per_night integer not null check (price_per_night > 0),
  amount integer not null,
  requested_by text not null references public.users (id),
  requested_at timestamptz not null,
  method text check (method in ('cash', 'paybill')),
  mpesa_code text,
  shift_id text references public.shifts (id),
  paid_by text references public.users (id),
  paid_at timestamptz,
  receipt_number text unique,
  payout_phone text,
  print_count integer not null default 0,
  server_seq bigint not null default nextval('public.sync_seq'),
  check (amount = nights * price_per_night),
  check ((paid_at is null) = (method is null)),
  check ((paid_at is null) = (shift_id is null)),
  check ((paid_at is null) = (paid_by is null)),
  check ((paid_at is null) = (receipt_number is null)),
  check ((method is not distinct from 'paybill') = (mpesa_code is not null)),
  check ((method is not distinct from 'paybill') = (payout_phone is not null))
);
create unique index refunds_mpesa_code_nocase on public.refunds (upper(mpesa_code));
create index refunds_shift on public.refunds (shift_id);

create table public.price_requests (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  category_id text not null references public.bed_categories (id),
  old_price integer not null check (old_price between 1 and 100000),
  new_price integer not null check (new_price between 1 and 100000),
  reason text,
  requested_by text not null references public.users (id),
  requested_at timestamptz not null,
  withdrawn_at timestamptz,
  withdrawn_by text references public.users (id),
  withdraw_reason text,
  server_seq bigint not null default nextval('public.sync_seq'),
  check (new_price <> old_price),
  check (reason is null or (reason = trim(reason) and length(reason) between 1 and 200)),
  check ((withdrawn_at is null) = (withdrawn_by is null)),
  check (withdrawn_at is not null or withdraw_reason is null)
);
create index price_requests_category on public.price_requests (category_id);

create table public.housekeeping_tasks (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  bed_id text not null references public.beds (id),
  housekeeper_id text not null references public.housekeepers (id),
  assigned_by text not null references public.users (id),
  assigned_at timestamptz not null,
  completed_at timestamptz,
  completed_by text references public.users (id),
  cancelled_at timestamptz,
  cancelled_by text references public.users (id),
  server_seq bigint not null default nextval('public.sync_seq'),
  check ((completed_at is null) = (completed_by is null)),
  check ((cancelled_at is null) = (cancelled_by is null)),
  check (completed_at is null or cancelled_at is null)
);
create index housekeeping_tasks_bed on public.housekeeping_tasks (bed_id);
create unique index housekeeping_tasks_one_open_per_bed on public.housekeeping_tasks (bed_id)
  where completed_at is null and cancelled_at is null;

create table public.inventory_items (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  name text not null unique,
  unit text not null,
  low_stock_level integer not null check (low_stock_level >= 0),
  is_active boolean not null default true,
  server_seq bigint not null default nextval('public.sync_seq')
);

create table public.inventory_movements (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  item_id text not null references public.inventory_items (id),
  direction text not null check (direction in ('in', 'out')),
  quantity integer not null check (quantity > 0),
  reason text not null,
  recorded_by text not null references public.users (id),
  server_seq bigint not null default nextval('public.sync_seq')
);
create index inventory_movements_item on public.inventory_movements (item_id);

-- ── Supervisor and owner records ───────────────────────────────────────

create table public.voids (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  target_type text not null check (target_type in ('payment', 'stay', 'refund')),
  target_id text not null,
  reason text not null check (length(trim(reason)) > 0),
  voided_by text not null references public.users (id),
  voided_at timestamptz not null,
  server_seq bigint not null default nextval('public.sync_seq'),
  unique (target_type, target_id)
);

create table public.expenses (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  category text not null check (category in
    ('laundry', 'utilities', 'wages', 'supplies', 'repairs', 'other')),
  amount integer not null check (amount > 0),
  spent_on text not null check (spent_on ~ '^[0-9]{4}-[0-1][0-9]-[0-3][0-9]$'),
  note text,
  recorded_by text not null references public.users (id),
  server_seq bigint not null default nextval('public.sync_seq')
);

create table public.refund_decisions (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  refund_id text not null unique references public.refunds (id),
  decision text not null check (decision in ('approved', 'rejected')),
  note text,
  decided_by text not null references public.users (id),
  decided_at timestamptz not null,
  server_seq bigint not null default nextval('public.sync_seq'),
  check (decision = 'approved' or coalesce(length(trim(note)), 0) > 0)
);

create table public.price_decisions (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  request_id text not null unique references public.price_requests (id),
  decision text not null check (decision in ('approved', 'rejected')),
  note text,
  decided_by text not null references public.users (id),
  decided_at timestamptz not null,
  server_seq bigint not null default nextval('public.sync_seq'),
  check (decision = 'approved' or coalesce(length(trim(note)), 0) > 0)
);

-- ── Audit ──────────────────────────────────────────────────────────────

create table public.audit_log (
  id text primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  device_id text not null,
  at timestamptz not null,
  operation_id text not null,
  user_id text references public.users (id),
  action text not null,
  entity text not null,
  entity_id text not null,
  before_json text,
  after_json text not null,
  server_seq bigint not null default nextval('public.sync_seq')
);
create index audit_log_at on public.audit_log (at);
create index audit_log_user on public.audit_log (user_id);
create index audit_log_action on public.audit_log (action);
create index audit_log_entity on public.audit_log (entity, entity_id);
create index audit_log_operation on public.audit_log (operation_id);

-- ── server_seq on every change ─────────────────────────────────────────

create function app_private.stamp_server_seq() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.server_seq := nextval('public.sync_seq');
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'users', 'settings', 'bed_categories', 'rooms', 'beds', 'housekeepers',
    'guests', 'shifts', 'stays', 'payments', 'stay_charges', 'refunds',
    'price_requests', 'housekeeping_tasks', 'inventory_items',
    'inventory_movements', 'voids', 'expenses', 'refund_decisions',
    'price_decisions', 'audit_log'
  ] loop
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function app_private.stamp_server_seq()',
      t || '_server_seq', t);
    execute format('create index %I on public.%I (server_seq)', t || '_seq', t);
  end loop;
end $$;
