# Cloud sync

The desk works offline and sends everything it writes to Supabase. The owner's decisions and prices are written in the cloud first, so the desk and (later) the owner's phone always agree on who decided first. **Sync-1** brought connecting, the first upload, pushing, the heartbeat and the owner's cloud-first writes; **sync-2** the desk's pull (decisions and prices made on the phone) and the clock check.

## How it works

- **Direction.** The desk pushes every row it writes (the outbox, oldest first, 200 rows per call, all or nothing per call). Only the owner's path writes `refund_decisions`, `price_decisions` and category prices. Staff logins never leave the desk: the cloud has no password hashes.
- **Order and retries.** A push is an upsert by id that only applies a newer `updated_at`, so a batch sent twice (the answer was lost) changes nothing. Rows that never change are insert-only in the cloud: `audit_log`, the decisions, `stay_charges` and `voids`; `payments` too, except `print_count` (reprints say COPY), which only ever goes up. Offline, changes wait; retries back off 5 s, 10 s, 20 s … up to 5 min. A row the cloud refuses **stops the queue** (later rows wait behind it; nothing is skipped) and the pill says "Sync problem · details".
- **First upload.** When the owner connects the desk, a snapshot of every synced table goes up, parents first, with progress on the pill. Progress is saved per table (`sync_state`), so a power cut or a lost connection resumes, never restarts. The desk's tables go up under the desk's own sign-in; the decisions made before connecting, and the current prices, go up under the owner's sign-in. Then the outbox rows the snapshot covered (up to the highest `seq` when it started) are marked sent; anything written during the upload goes up through the normal push.
- **Cloud first.** Approving or rejecting a refund or price request, and changing prices, call the cloud first (the first decision anywhere wins), then write the same row here. Offline: "Approving needs an internet connection." A loser is told "Already decided by Amina Owner · Fri 16 Oct, 10:42 (rejected)." Withdrawing a price request (the supervisor's, or closing its category) goes to the cloud first too, so a withdrawal and the owner's decision can't both stand.
- **Heartbeat.** Every ~5 minutes the desk reports its last push, its queue and any problem to `desk_status`, even while the queue is stopped. The owner can read it ("Desk last synced 3 h ago · sync problem").
- **Pull.** After each push and every 30 s (and on start and "Try again now"), the desk pulls what the owner's side wrote since its cursor (`server_seq`, never a clock): refund and price decisions, category prices (only the price; the desk's own columns never come back) and the phone's audit rows. Page by page (500 rows), so days offline simply catch up; each page and the cursor are written in one transaction, so a crash replays a page harmlessly. Rows already here (by id) are skipped: everything this desk wrote cloud-first comes back that way. Pulled rows get no audit or outbox rows and are never pushed back. The pull runs even while the push queue is stopped; a decision that clashes with a different one here stops the pull (and only the pull) with "Sync problem · details", and nothing is overwritten.
- **Live at the desk.** A pulled approval moves the refund to Refunds → TO PAY and updates the badge; a rejection shows the owner's reason; a price applies to new check-ins at once (a check-in screen still showing the old price is refused at save: "Deluxe is now KES 750 a night. Check the total and save again."). The owner's Prices card refreshes: an untouched field takes the new price, a typed one keeps its value with the new price in its "was" hint.
- **The order rule.** A sequence number is taken when a row is written, not when it commits, so a late commit could land behind a desk's cursor. Every function that writes a pulled row (`decide_refund`, `decide_price_request`, `set_prices`, `import_owner_rows`, and any new one) takes `pg_advisory_xact_lock(hashtext('lodging.owner_writes'))` before its first write, so they commit in order. `supabase/tests/pull_test.sql` inspects every function and fails if one doesn't.
- **Clock check.** Each pull answers with the server's time (`clock_timestamp()`); the desk compares it with its own, halfway through the request (a request slower than 10 s is ignored). More than 5 minutes off either way: the pill says "PC clock 12 min slow · fix" (after a sync problem, before online/offline), the Sync panel gives the fix ("Windows Settings → Time & language → Sync now"), and `sync.clock_warning` is recorded once per episode (remembered across restarts). It clears only once the PC is within 4 minutes. The offset (PC minus server, seconds) goes in the heartbeat (`desk_status.clock_offset_seconds`), so the owner sees if the desk clock was moved: it changes checkout and late charges. It only warns; nothing is blocked.
- **Who can do what.** RLS is on for every table with no write policies: every write goes through a function that checks the caller's role. The owner reads everything (guests' phones and IDs included); the desk reads only what `pull_changes` returns; anonymous callers can't read or call anything. The service key is used only inside the `connect-desk` Edge Function.

## Environments

- **This Supabase project ("UB40 Lodging", eu-central-1) is dev/staging.** It holds test data and the test owner account, and is where new migrations and the Edge Function are tried first.
- **Production will be a fresh project**, created in the hardening week: the same steps below (`db push`, deploy `connect-desk`, sign-ups off), then the desk connected to it with a new install code.
- **Use the owner's real email there.** The owner's cloud account is created by the first connect, and **can't be changed later**: there is one owner per project (`app_private.owner`), and every later connect must use the same email. A forgotten password is reset by email, so it must be an inbox the owner reads.

## The desk's identity

- **One cloud account per desk** (`<device id>@desk.lodging.invalid`), created by `connect-desk`. Its secret is stored with `flutter_secure_storage`: encrypted, with the key in the **Windows user's Credential Manager**.
- **Run the desk under one Windows user.** Under another Windows user the secret is missing; the pill shows "Sync problem · details" and the owner uses **Reconnect this desk** in the Sync panel (their email and desk password; the desk gets a new secret).
- **The owner's cloud account** is created when the owner first connects a desk, with the owner's email and the **same password** as on the desk. Signing in on the desk while online also signs the owner in to the cloud, quietly. If that sign-in is missing (signed in offline, or the password was changed on the phone), the first decision asks "Sign in to the cloud" once.

## The owner's phone

The owner's app (`lib/main_owner.dart`, Android and web; `features/owner_app`) has no database: it reads the cloud and decides through the same functions as the desk. It is built with the same `secrets.json` (`flutter run -t lib/main_owner.dart --dart-define-from-file=secrets.json`); release builds are in `docs/release.md`.

- **Sign-in.** The owner's cloud email and password (the desk's owner password). Only an account whose `app_metadata.role` is `owner` gets in. The session is kept in the phone's secure storage, so the owner stays signed in until **Sign out** (More); if the cloud stops renewing it (e.g. the password was changed elsewhere), the app goes back to sign-in.
- **Today.** The desk's cards (`dashboard/presentation/today_cards.dart`), worked out by the same `dashboard/domain` functions, plus under Needs your attention: shifts closed short in the last 7 days and payments voided in the last 7 days. The header shows when the figures were loaded ("Updated 4 min ago") and the desk's last heartbeat ("Desk online · 3 changes waiting", or "Desk offline · last seen today 09:18" after 11 minutes without one). Today reloads when the app opens, when it comes back to the front, on pull-down and every 60 s.
- **Offline.** The last figures stay on screen, in memory only, marked "Offline · showing today 09:30". Deciding needs the internet ("Approving needs an internet connection.").
- **Refunds.** The desk's "Refund request" layout (`refunds/presentation/refund_detail_body.dart`) and rules (`refunds/domain/refund.dart`), then `decide_refund` with the server's time (`server_time()`, never the phone's clock), this install's id as `device_id` (made once, kept in secure storage) and its `refund.approve` / `refund.reject` audit row. The first decision anywhere wins; the desk pulls it.
- **Privacy.** The phone downloads only the columns a screen shows. It never reads `guests` (only the `owner_guests` view: id, name and masked phone, with the caller's row-level security), never an ID number, a full phone, the M-Pesa payout phone or a password hash, and never `*`. `test/policy/owner_app_test.dart` fails if its code names any of them, and checks the app imports nothing of the desk's database, sync or files; `FakeOwnerCloud` refuses them in every test. Nothing guest-related is written to the phone's storage: only the sign-in session and the install id.
- **Forgot password.** There is no reset screen or recovery email (the apps have no page to land on). You reset it by hand in the Supabase dashboard, **SQL Editor**, choosing a temporary password and giving it to the owner in person or by phone:

  ```sql
  update auth.users
  set encrypted_password = extensions.crypt('<temporary password>', extensions.gen_salt('bf'))
  where email = '<the owner''s email>';
  ```

  Then delete that query from the SQL Editor's history. The owner signs in with it and changes it (Change password, owner-app-3). Until owner-app-3 the desk keeps accepting its own copy of the old password; set the same one there too (Change password on the desk).

## Setting up the cloud (once)

You need the Supabase project ("UB40 Lodging", eu-central-1) and Node.js (for `npx`). Docker is not needed.

1. **Turn off public sign-ups.** Dashboard → Authentication → Sign In / Providers → turn off "Allow new users to sign up". Only `connect-desk` creates accounts.
2. **Link the project and apply the migrations.** In the repo root (the folder with `supabase/`):

   ```bash
   npx supabase@2.121.0 login
   ```

   ```bash
   npx supabase@2.121.0 link --project-ref <your-project-ref>
   ```

   ```bash
   npx supabase@2.121.0 db push
   ```

3. **Deploy `connect-desk`.**

   ```bash
   npx supabase@2.121.0 functions deploy connect-desk --no-verify-jwt --use-api
   ```

   **Function secrets:** nothing to set. Hosted Edge Functions get `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` automatically; check with:

   ```bash
   npx supabase@2.121.0 secrets list
   ```

   Keep the project's legacy API keys (anon and service_role) enabled: the function reads those two variables.

4. **Make an install code** for each desk you connect. Dashboard → SQL Editor:

   ```sql
   select app_private.new_install_code();
   ```

   It returns the code and when it expires, e.g. `7KQ2-M9XD-4HPA · expires Fri 30 Oct 2026, 14:05 (Nairobi)`. Copy the code (the part before the dot) and keep it until you connect the desk:

   - It's shown only once (only its hash is kept) and works once.
   - It expires **7 days** after it was made. An expired or lost code can't be recovered: run the query again for a new one. Unused codes are simply never used.
   - Connecting with it: the owner types it in the desk's Sync panel (step 6). A wrong code, a used one and an expired one all get "That install code isn't valid, has expired or has been used."
   - After **10 failed tries in an hour** for the same owner email (wrong code, wrong password), `connect-desk` refuses with "Too many tries. Wait an hour and try again." Every try is recorded (`app_private.connect_attempts`).

5. **Give the desk its settings.** Create `lodging_pos/secrets.json` (untracked; `.gitignore` blocks `secrets*.json`) with the project URL and the **anon** key (Dashboard → Project Settings → API):

   ```json
   {
     "SUPABASE_URL": "https://<your-project-ref>.supabase.co",
     "SUPABASE_ANON_KEY": "<anon key>"
   }
   ```

   Run and build with it:

   ```bash
   flutter run -d windows --dart-define-from-file=secrets.json
   ```

   ```bash
   flutter build windows --release --dart-define-from-file=secrets.json
   ```

   Without it the app works as before and the pill says "Sync not set up".

6. **Connect the desk.** The owner signs in on the desk, clicks the sync pill, and enters the install code, their email and their desk password. The first upload starts at once; keep the desk on until the pill says "Online".

## Tests

- `test/core/sync/` runs the engine and the cloud-first writes against `FakeCloud` (`test/helpers/fake_cloud.dart`), which keeps the cloud's rules.
- `supabase/tests/` (pgTAP) runs the real migrations on a local Supabase in CI (job `cloud`): who can read and write, the sync functions, first-decision-wins, the mirrored rules. Locally it needs Docker (`npx supabase@2.121.0 db start`, then `npx supabase@2.121.0 test db`).
