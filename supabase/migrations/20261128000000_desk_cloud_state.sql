-- story/desk-db-guards-2: what the cloud holds from the calling desk, so the
-- desk can tell whether its database file is behind the cloud (an older copy
-- put in its place). The desk asks with its own sign-in, at start and before
-- the first push of each session (docs/sync.md, "Behind the cloud"). Only
-- ids and figures come back: the ids of its 50 newest audit rows (the desk
-- never deletes one, so any it lacks proves an older copy, whatever the
-- clocks say), its newest audit time, its highest receipt number and its
-- open shift.

create function public.desk_cloud_state()
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_device text := app_private.require_desk();
begin
  return jsonb_build_object(
    'recent_audit_ids', coalesce((
      select jsonb_agg(r.id order by r.created_at desc) from (
        select a.id, a.created_at from public.audit_log a
        where a.device_id = v_device
        order by a.created_at desc
        limit 50) r), '[]'::jsonb),
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

revoke execute on function public.desk_cloud_state() from public, anon;
grant execute on function public.desk_cloud_state() to authenticated;
