-- owner-app-1: what the owner's phone needs that the tables don't give it.
-- See docs/sync.md, "The owner's phone".

-- ── The server's time ──────────────────────────────────────────────────
-- The phone stamps its decisions with the server's time, not its own clock
-- (clock_timestamp: the time of answering, as pull_changes gives the desk).
create function public.server_time() returns timestamptz
language sql volatile set search_path = '' as $$
  select clock_timestamp()
$$;

revoke execute on function public.server_time() from public, anon;
grant execute on function public.server_time() to authenticated;

-- ── Guests, masked ─────────────────────────────────────────────────────
-- The phone shows a guest's name and masked phone only, and never downloads
-- the full phone or the ID number: it reads this view, never public.guests.
-- The mask is core/contacts/phone.dart's maskPhone: the first four digits
-- (after any +), •••, the last three; "•••" when shorter than 8 digits.
-- security_invoker: the caller's row-level security on guests applies, so
-- only the owner sees rows.
create view public.owner_guests with (security_invoker = true) as
  select g.id, g.full_name,
    case when length(d.digits) < 8 then '•••'
      else d.plus || left(d.digits, 4) || ' ••• ' || right(d.digits, 3)
    end as phone_masked
  from public.guests g,
    lateral (select
      case when g.phone like '+%' then '+' else '' end as plus,
      case when g.phone like '+%' then substr(g.phone, 2) else g.phone end
        as digits) d;

revoke all on public.owner_guests from anon, authenticated;
grant select on public.owner_guests to authenticated;
