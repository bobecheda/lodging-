# Cloud sync

The desk works offline and sends everything it writes to Supabase. The owner's decisions and prices are written in the cloud first, so the desk and (later) the owner's phone always agree on who decided first. This is **sync-1**: connecting, the first upload, pushing, the heartbeat and the owner's cloud-first writes. **Sync-2** adds the desk's pull (decisions and prices made on the phone) and the clock check.

## How it works

- **Direction.** The desk pushes every row it writes (the outbox, oldest first, 200 rows per call, all or nothing per call). Only the owner's path writes `refund_decisions`, `price_decisions` and category prices. Staff logins never leave the desk: the cloud has no password hashes.
- **Order and retries.** A push is an upsert by id that only applies a newer `updated_at`, so a batch sent twice (the answer was lost) changes nothing. Offline, changes wait; retries back off 5 s, 10 s, 20 s … up to 5 min. A row the cloud refuses **stops the queue** (later rows wait behind it; nothing is skipped) and the pill says "Sync problem · details".
- **First upload.** When the owner connects the desk, a snapshot of every synced table goes up, parents first, with progress on the pill. Progress is saved per table (`sync_state`), so a power cut or a lost connection resumes, never restarts. The desk's tables go up under the desk's own sign-in; the decisions made before connecting, and the current prices, go up under the owner's sign-in. Then the outbox rows the snapshot covered (up to the highest `seq` when it started) are marked sent; anything written during the upload goes up through the normal push.
- **Cloud first.** Approving or rejecting a refund or price request, and changing prices, call the cloud first (the first decision anywhere wins), then write the same row here. Offline: "Approving needs an internet connection." A loser is told "Already decided by Amina Owner · Fri 16 Oct, 10:42 (rejected)." Withdrawing a price request (the supervisor's, or closing its category) goes to the cloud first too, so a withdrawal and the owner's decision can't both stand.
- **Heartbeat.** Every ~5 minutes the desk reports its last push, its queue and any problem to `desk_status`, even while the queue is stopped. The owner can read it ("Desk last synced 3 h ago · sync problem").
- **Who can do what.** RLS is on for every table with no write policies: every write goes through a function that checks the caller's role. The owner reads everything (guests' phones and IDs included); the desk reads nothing yet; anonymous callers can't read or call anything. The service key is used only inside the `connect-desk` Edge Function.

## The desk's identity

- **One cloud account per desk** (`<device id>@desk.lodging.invalid`), created by `connect-desk`. Its secret is stored with `flutter_secure_storage`: encrypted, with the key in the **Windows user's Credential Manager**.
- **Run the desk under one Windows user.** Under another Windows user the secret is missing; the pill shows "Sync problem · details" and the owner uses **Reconnect this desk** in the Sync panel (their email and desk password; the desk gets a new secret).
- **The owner's cloud account** is created when the owner first connects a desk, with the owner's email and the **same password** as on the desk. Signing in on the desk while online also signs the owner in to the cloud, quietly. If that sign-in is missing (signed in offline, or the password was changed on the phone), the first decision asks "Sign in to the cloud" once.

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

   It returns a code like `7KQ2-M9XD-4HPA`, shown only once (only its hash is kept). It works once.

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
