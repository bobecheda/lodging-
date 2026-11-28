-- story/desk-db-guards-2: what the cloud holds from the calling desk, so the
-- desk can tell whether its database file is behind the cloud (an older copy
-- put in its place). The desk asks with its own sign-in, at start and before
-- the first push of each session (docs/sync.md, "Behind the cloud"). Only
-- figures come back: how many of its audit rows are newer than its newest,
-- its newest audit time, its highest receipt number and its open shift.

create function public.desk_cloud_state(p_after timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_device text := app_private.require_desk();
begin
  return jsonb_build_object(
    'newer_audit_rows', (
      select count(*) from public.audit_log a
      where a.device_id = v_device
        and (p_after is null or a.created_at > p_after)),
    'last_audit_at', (
      select max(a.created_at) from public.audit_log a
      where a.device_id = v_device),
    'top_receipt', (
      select r.receipt_number from (
        select p.receipt_number from public.payments p
        where p.device_id = v_device
        union all
        select f.receipt_number from public.refunds f
        where f.device_id = v_device and f.receipt_number is not null) r
      order by substring(r.receipt_number from '(\d+)$')::bigint desc nulls last
      limit 1),
    'open_shift', (
      select s.id from public.shifts s
      where s.device_id = v_device and s.status = 'open'
      limit 1));
end $$;

revoke execute on function public.desk_cloud_state(timestamptz) from public, anon;
grant execute on function public.desk_cloud_state(timestamptz) to authenticated;
