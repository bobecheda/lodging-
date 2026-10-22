-- The desk's database guards (lib/core/database/triggers.drift), mirrored.
--
-- Not mirrored: the "*_stamped_update" triggers. In the cloud every write
-- goes through the sync functions, which only update a row when the
-- incoming updated_at is newer (0200_functions), so a replayed batch is a
-- no-op instead of an error.
--
-- The first upload (a snapshot of the desk's rows in their final state)
-- sets app.importing for its own transaction; the lifecycle triggers below
-- that judge a single step (requested-before-paid, one open request,
-- starts-open) stand aside for it. Rows that never change and never get
-- deleted are guarded even then.

create function app_private.importing() returns boolean
language sql stable set search_path = '' as $$
  select coalesce(current_setting('app.importing', true), '') = 'on'
$$;

create function app_private.refuse() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception '%', tg_argv[0] using errcode = 'P0001';
end $$;

-- Never deleted (BR-11); audit_log append-only; decisions final.
do $$
declare t text;
begin
  foreach t in array array[
    'stays', 'payments', 'stay_charges', 'voids', 'audit_log', 'refunds',
    'refund_decisions', 'price_requests', 'price_decisions'
  ] loop
    execute format(
      'create trigger %I before delete on public.%I for each row '
      'execute function app_private.refuse(%L)',
      t || '_no_delete', t, t || ' rows are never deleted');
  end loop;
end $$;

create trigger audit_log_no_update before update on public.audit_log
  for each row execute function app_private.refuse('audit_log is append-only');
create trigger refund_decisions_no_update before update on public.refund_decisions
  for each row execute function app_private.refuse('refund_decisions rows are never edited');
create trigger price_decisions_no_update before update on public.price_decisions
  for each row execute function app_private.refuse('price_decisions rows are never edited');

-- v5 (FD-11): a closed shift never changes.
create function app_private.shifts_closed_final() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.status = 'closed' then
    raise exception 'a closed shift cannot be changed';
  end if;
  return new;
end $$;
create trigger shifts_closed_final before update on public.shifts
  for each row execute function app_private.shifts_closed_final();

-- Refunds (BR-8a, BR-8b). Note: INSERT ... ON CONFLICT DO UPDATE fires the
-- BEFORE INSERT triggers even when the row exists, so insert checks skip
-- rows already here.
create function app_private.refunds_rules() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    -- An upsert of a row already here fires this too; its update judges it.
    if new.paid_at is not null and not app_private.importing()
      and not exists (select 1 from public.refunds where id = new.id) then
      raise exception 'a refund is requested before it is paid';
    end if;
    return new;
  end if;
  if new.stay_id is distinct from old.stay_id
    or new.nights is distinct from old.nights
    or new.price_per_night is distinct from old.price_per_night
    or new.amount is distinct from old.amount
    or new.requested_by is distinct from old.requested_by
    or new.requested_at is distinct from old.requested_at then
    raise exception 'refund terms cannot change';
  end if;
  if old.paid_at is not null and (
    new.paid_at is distinct from old.paid_at
    or new.method is distinct from old.method
    or new.mpesa_code is distinct from old.mpesa_code
    or new.shift_id is distinct from old.shift_id
    or new.paid_by is distinct from old.paid_by
    or new.receipt_number is distinct from old.receipt_number
    or new.payout_phone is distinct from old.payout_phone) then
    raise exception 'refund is already paid';
  end if;
  if old.paid_at is null and new.paid_at is not null
    and not app_private.importing()
    and not exists (
      select 1 from public.refund_decisions
      where refund_id = new.id and decision = 'approved') then
    raise exception 'refund is not approved';
  end if;
  return new;
end $$;
create trigger refunds_rules before insert or update on public.refunds
  for each row execute function app_private.refunds_rules();

-- An M-Pesa code is used once across payments and refund payouts (BR-10).
create function app_private.mpesa_code_unused() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.mpesa_code is not null and (
    (tg_table_name = 'payments' and exists (
      select 1 from public.refunds
      where upper(mpesa_code) = upper(new.mpesa_code)))
    or (tg_table_name = 'refunds' and exists (
      select 1 from public.payments
      where upper(mpesa_code) = upper(new.mpesa_code)))) then
    raise exception 'M-Pesa code already used';
  end if;
  return new;
end $$;
create trigger payments_mpesa_code_unused before insert or update of mpesa_code
  on public.payments for each row execute function app_private.mpesa_code_unused();
create trigger refunds_mpesa_code_unused before insert or update of mpesa_code
  on public.refunds for each row execute function app_private.mpesa_code_unused();

-- Price requests (BR-2, v8).
create function app_private.price_requests_rules() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    -- An upsert of a row already here fires this too; its update judges it.
    if app_private.importing()
      or exists (select 1 from public.price_requests where id = new.id) then
      return new;
    end if;
    if new.withdrawn_at is not null then
      raise exception 'a price request starts open';
    end if;
    if exists (
      select 1 from public.price_requests p
      where p.category_id = new.category_id and p.withdrawn_at is null
        and not exists (
          select 1 from public.price_decisions d where d.request_id = p.id)) then
      raise exception 'the category already has an open price request';
    end if;
    return new;
  end if;
  if new.category_id is distinct from old.category_id
    or new.old_price is distinct from old.old_price
    or new.new_price is distinct from old.new_price
    or new.reason is distinct from old.reason
    or new.requested_by is distinct from old.requested_by
    or new.requested_at is distinct from old.requested_at then
    raise exception 'price request terms cannot change';
  end if;
  if old.withdrawn_at is not null and (
    new.withdrawn_at is distinct from old.withdrawn_at
    or new.withdrawn_by is distinct from old.withdrawn_by
    or new.withdraw_reason is distinct from old.withdraw_reason) then
    raise exception 'price request is already withdrawn';
  end if;
  if old.withdrawn_at is null and new.withdrawn_at is not null
    and exists (select 1 from public.price_decisions where request_id = new.id) then
    raise exception 'price request is already decided';
  end if;
  return new;
end $$;
create trigger price_requests_rules before insert or update on public.price_requests
  for each row execute function app_private.price_requests_rules();

create function app_private.price_decisions_not_withdrawn() returns trigger
language plpgsql set search_path = '' as $$
begin
  if exists (
    select 1 from public.price_requests
    where id = new.request_id and withdrawn_at is not null) then
    raise exception 'price request was withdrawn';
  end if;
  return new;
end $$;
create trigger price_decisions_not_withdrawn before insert on public.price_decisions
  for each row execute function app_private.price_decisions_not_withdrawn();
