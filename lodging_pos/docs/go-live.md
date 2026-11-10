# Go-live runbook (UB40, 20 Nov 2026)

The steps to put lodging_pos live at UB40 on a **fresh production Supabase project**, in order, with a check after each. It builds on `docs/sync.md` (the cloud) and `docs/release.md` (builds, installs, checklists); where a step is already there, this file points to it.

Tick each box as you go. Don't skip a check: each one is cheap now and expensive on site.

**Who does what:** you run every cloud step (dashboard, SQL, CLI); nobody else needs a service key, and none goes into an app or a file in the repo.

## 0. The freeze (Tue 17 Nov)

Voids, then the blind cash count with the supervisor's review, are built before the freeze. Tue 17 Nov is a full regression pass (both builds, network off, the smoke test below) and the tag, with no new features. Expenses, monthly reports and AD-11 come after go-live.

- [ ] `main` is green in CI (`checks`, `cloud`, `owner-app-build`, `windows-build`).
- [ ] Remove the dev project's link files from the repo, if not done yet (see "Pointers to the dev project" at the end).
- [ ] Raise the version for the release: `pubspec.yaml` `version: 1.1.0+3` (the `+3` must be higher than any APK already installed on a phone). Merge it.
- [ ] Tag the go-live commit and build only from the tag. **`v1.1-golive` replaces `v1.0-golive`**: that tag (on `944ca87`, version `1.0.0+2`, pushed 7 Nov before go-live moved) stays where it is and is never moved or built from.

  ```bash
  git checkout main
  ```

  ```bash
  git pull --ff-only
  ```

  ```bash
  git tag -a v1.1-golive -m "UB40 go-live"
  ```

  ```bash
  git push origin v1.1-golive
  ```

- [ ] The upload key (`upload-keystore.jks`) and its passwords are backed up in two places (`docs/release.md`).
- [ ] The owner has confirmed **in writing** (a message you keep) the **email for their cloud account**: an inbox they control and read. It can't be changed later (one owner per project), and a forgotten password is reset through it.
- [ ] **MFA is on for the developer's Supabase account** (Account → Security → Multi-factor authentication), the only account that can change the production project.
- [ ] **Tell the owner where the data is stored:** guests' names, phones and ID numbers, payments and staff, in Supabase's **eu-west-1 (Ireland)** region, under EU data protection law, encrypted at rest; the desk PC at UB40 keeps its own full copy and its backups. Note that you told them, and when.

## 1. The production Supabase project (you, in the dashboard)

- [ ] **Plan: Supabase Pro** for the organisation that holds production. The Free plan is **not acceptable** for production: it pauses a project after a week without activity (the desk would stop syncing), keeps no daily backups, and has no leaked-password protection. Pro gives daily backups (kept 7 days), no pausing, and leaked-password protection.
- [ ] Create a **new** project (not the dev one): organisation "UB40 Lodging", region **eu-west-1 (Ireland)**, a strong database password kept in your password manager. Name it e.g. "UB40 Lodging – production".
  - **Why eu-west-1:** it is the region of the dev project, where every sync, phone and desk test so far ran over Kenyan connections, so production behaves as tested; and the data sits under EU data protection law. Supabase has no region in Kenya. If you pick another region, tell the owner (week-before list) and note it here.
- [ ] Authentication → Sign In / Providers → turn **off** "Allow new users to sign up". Only `connect-desk` creates accounts.
- [ ] Authentication → Passwords: leaked password protection **on** (Pro has it); minimum length at least 8 (the apps ask for 8).
- [ ] Database → Backups: daily backups are listed (Pro). Point-in-time recovery is optional extra cost; daily is enough with the desk's own backups.
- [ ] Project Settings → API: keep the **legacy API keys** (anon and service_role) enabled; `connect-desk` reads those two.
- [ ] Note the new **project ref** (Project Settings → General) for the next step.

## 2. Migrations and the Edge Function (you, CLI, from the repo root)

Use the tag, so production gets exactly what was tested:

```bash
git checkout v1.1-golive
```

Link the CLI to **production** (this replaces the dev link on this PC):

```bash
npx supabase@2.121.0 login
```

```bash
npx supabase@2.121.0 link --project-ref <production-ref>
```

Check it says the production project before pushing anything:

```bash
npx supabase@2.121.0 projects list
```

(The linked project has a ● next to it.) Apply every migration, in order:

```bash
npx supabase@2.121.0 db push
```

- [ ] It lists and applies these, in this order, with no error:
  `20261023000000_tables`, `20261023000100_rules`, `20261023000200_sync`, `20261024000000_hardening`, `20261025000000_pull`, `20261026000000_owner_app`, `20261027000000_change_prices`, `20261028000000_password_changes`, `20261029000000_voids`, `20261110000000_cash_drawer`, `20261110000100_cash_drawer_defaults`.
  The desk build at the tag is schema **v10** (the blind close and the drawer's counts). Story B3 (review decisions) adds one more cloud migration here if it makes the freeze; this list and the count below are updated in that PR.
- [ ] Check in the SQL Editor that they're all recorded (11 rows):

  ```sql
  select version from supabase_migrations.schema_migrations order by version;
  ```

Deploy `connect-desk`:

```bash
npx supabase@2.121.0 functions deploy connect-desk --no-verify-jwt --use-api
```

- [ ] **Its secrets:** nothing to set by hand. Hosted Edge Functions get `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` automatically. Check they're listed:

  ```bash
  npx supabase@2.121.0 secrets list
  ```

- [ ] Dashboard → Edge Functions → `connect-desk` shows "Verify JWT" **off**.

### Advisors

Dashboard → Advisors → Security Advisor → refresh.

- [ ] **No** "RLS disabled in public", "Policy exists RLS disabled", "Security definer view" or "Function search path mutable" findings. Any of those: stop and tell me before going on.
- [ ] Expected, and fine (by design: every write goes through these, each checking the caller's role): warnings that these SECURITY DEFINER functions can be called by signed-in users: `push_changes`, `import_desk_rows`, `import_owner_rows`, `finish_first_upload`, `first_upload_done`, `withdraw_price_request`, `desk_heartbeat`, `decide_refund`, `decide_price_request`, `set_prices`, `change_prices`, `pull_changes`, `record_password_change`.
- [ ] No "Leaked password protection disabled" warning (it is on, step 1).

Switch your PC back to the dev project afterwards, so a later `db push` for development can't land on production:

```bash
npx supabase@2.121.0 link --project-ref <dev-ref>
```

## 3. The production builds (this PC, from the tag)

- [ ] Make `lodging_pos/secrets.prod.json` (untracked: `.gitignore` blocks `secrets*.json`) with the **production** URL and anon key (Project Settings → API):

  ```json
  {
    "SUPABASE_URL": "https://<production-ref>.supabase.co",
    "SUPABASE_ANON_KEY": "<production anon key>"
  }
  ```

  Keep your dev file as `secrets.json`; never mix them up. Every production build below names `secrets.prod.json`.

From `lodging_pos`, on the tag (`git checkout v1.1-golive`):

```bash
flutter build apk --release -t lib/main_owner.dart --dart-define-from-file=secrets.prod.json
```

- [ ] Signed with your key (the owner shown is your name, not "Android Debug"):

  ```bash
  keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk
  ```

- [ ] Copy `build\app\outputs\flutter-apk\app-release.apk` somewhere safe, renamed `lodging-owner-1.1.apk`.

```bash
flutter build windows --release --dart-define-from-file=secrets.prod.json
```

- [ ] Copy the whole `build\windows\x64\runner\Release` folder to a USB drive as `UB40-Desk-1.1`, and `vc_redist.x64.exe` (Microsoft) next to it.
- [ ] Quick check on this PC before leaving: run `Release\lodging_pos.exe` from the USB copy; it should open on "Create the owner's account" **only if this PC has no desk data** for that Windows user; otherwise just close it. Don't connect it to production.

## 4. On site: the UB40 PC

Make the install code shortly before (it lasts 7 days; it's shown once). Production SQL Editor:

```sql
select app_private.new_install_code();
```

- [ ] Code written down (the part before " · expires …").

On the UB40 PC (`docs/release.md`, "First run on a new PC"):

- [ ] Windows date, time and time zone (Nairobi, UTC+3) right and set automatically.
- [ ] The desk runs under **one** Windows user, always the same (the desk's cloud secret lives in that user's Credential Manager).
- [ ] VC++ 2015–2022 Redistributable (x64) installed.
- [ ] `UB40-Desk-1.1` copied whole to `C:\UB40\Desk`; shortcut to `lodging_pos.exe` on the desktop and in Startup if wanted.
- [ ] Printer installed in Windows; a test page prints.

First run:

- [ ] "Create the owner's account": the owner's full name, username, password (the same password they'll use on the phone), lodging name **UB40**.
- [ ] Sign in as the owner → sync pill → **Connect**: the install code, the owner's real email, the owner's desk password. Wait until the pill says **"Online · synced just now"**.
- [ ] Owner → Staff: add the **supervisor** (they change their password at first sign-in).
- [ ] Sign in as the supervisor → Staff: add the **receptionists** and the housekeepers.
- [ ] **The starting cash, before the first shift:** the owner or supervisor counts all the cash actually in the drawer on the day, then Cash → **Starting cash** → enter the count → Save (`drawer.start`). Every float follows from it: no shift opens until it's saved, and the receptionist never types a float. It can be saved once; if the count was wrong, note it and correct it with the first drawer check (Story B2).
- [ ] Supervisor → Rooms: rooms and beds (A/B, category for each).
- [ ] Owner → Prices: the four categories' prices per night (VIP, Deluxe, Comfort, Normal; cloud-first, needs the internet).
- [ ] Supervisor → Settings: lodging details for receipts, grace minutes, idle lock, second backup folder (USB drive) if used.
- [ ] Backups card → "Back up now". **Where the first backup is saved:** on the UB40 PC in `%APPDATA%\com.lodging\lodging_pos\backups` (the desk's Windows user), and in the second backup folder if set, on a USB drive that **stays at UB40 and is kept by the owner** (or someone they name). The developer does not take a copy away: it holds guests' personal data. Check today's file is in both places.

## 5. Smoke test (desk + owner's phone side by side)

Use a test guest you will then check out; all money in this test is small and real (take KES 10 cash, or agree a test price with the owner first). After each desk action, pull down on the phone (or wait a minute) and check the phone column.

| # | At the desk | On the owner's phone |
|---|---|---|
| 1 | Receptionist opens a shift: no float to type (it is the starting cash). | More → Shifts: the shift is **OPEN**. |
| 2 | Check a test guest into a bed, 1 night, cash; receipt prints. | Beds: that bed **Occupied**. Today's money and Money: the amount, **Cash**. Audit trail: "Checked a guest in", "Took a payment", "Printed a receipt", on the desk. |
| 3 | Check the guest out early (the night not used): a refund is requested. | Beds: the bed **Needs cleaning**. Today → Needs your attention: **Refund to approve**, the guest's name and masked phone. |
| 4 | — | Open it → **Approve** (owner). |
| 5 | Within a minute: Refunds → **To pay** shows it; pay it in cash from the open shift; the REFUND receipt prints with "Approved by" the owner. | Money: **Refunds paid**; the net goes down. |
| 6 | Housekeeping: assign the bed, then mark it clean. | Beds: the bed **Ready**. Audit trail: "Assigned a cleaning", "Marked a bed clean". |
| 7 | Receptionist closes the shift with a blind count: the screen never shows what's expected. Count right → "Your count is recorded". (Also try a wrong first count on a test shift: "Your count doesn't match", no amount; the recount closes it.) The supervisor's Cash shows the chain: starting cash → opened → closed. | More → Shifts: the shift closed, "Exact" (or "KES … short/over"); a shortage also shows under Needs your attention. |
| 8 | A second test guest checked in (cash) by the receptionist; then the **supervisor** voids that stay (Voids → the receipt → Void stay…, reason "Smoke test"). The receipt shows VOID; the bed needs cleaning. | Money: the amount is gone again. Beds: the bed **Needs cleaning**. Audit trail: "Voided a record". No "Void not in the cloud" under Needs your attention. |
| 9 | Sync pill: **"Online · synced just now"**, nothing waiting (no "void not in the cloud"). | Header: "Desk online · up to date". |

- [ ] All 9 rows pass. Delete nothing: the test stays stay in the books, as every real record does (the first one has a refund, so it can't be voided; the owner can note it in the corrections book).

## 6. The owner's phone

`docs/release.md`, "Phone test checklist", on the **production** APK:

- [ ] If a dev or demo build is on the phone, uninstall it first (it holds a session for the dev project):

  ```bash
  adb uninstall com.lodging.lodging_pos
  ```

- [ ] Install `lodging-owner-1.0.apk` (`adb install -r …`, or copy it to the phone and open it).
- [ ] **Turn Wi-Fi off: mobile data only** for this check.
- [ ] Sign in with the owner's email and desk password: Today loads with the smoke test's figures.
- [ ] Swipe the app away completely, open it again: **still signed in** (this confirms the R8 rules for secure storage).
- [ ] Airplane mode: "Offline · showing …"; off again: pull down, "Updated just now".

## 7. If something fails on site (rollback)

The desk works fully offline and keeps every record itself; the cloud is a copy plus the owner's decisions (which the desk also keeps). So the lodging can always open, whatever the cloud does.

**Sync fails** (the pill shows "Sync problem · details", "Offline", or connecting is refused):

1. Keep working: check-ins, payments, receipts, shifts and housekeeping need no internet. The changes wait in the desk and go up later on their own. Only refund approval and price changes wait for the internet.
2. Read the Sync panel's message:
   - "That install code isn't valid, has expired or has been used": make a new code (step 4) and connect again.
   - "Too many tries. Wait an hour and try again": wait an hour (10 failed connects in an hour per owner email).
   - "That isn't your desk password": the owner's desk password, exactly as at the desk's sign-in.
   - "Sync not set up": this Release folder was built without `secrets.prod.json`: rebuild (step 3).
   - A refused row ("Sync problem · details" naming a table): take a photo of the panel and send it to me; don't reconnect or reset anything.
3. If it can't be fixed on the day: leave the desk **not connected** (or connected but offline). Everything still works locally; connect later with a new install code: the first upload sends everything made in between.

**The owner can't sign in on the phone:**

- "This build has no cloud set up": the APK was built without `secrets.prod.json`: rebuild (step 3).
- "Wrong email or password": the email must be the one used to connect the desk; the password is the desk password from that moment. Forgot it: `docs/sync.md`, "Forgot password".
- "This account isn't the owner's": the email belongs to another account; sign in with the owner's.
- Nothing loads, no error: check mobile data; the phone's date and time set automatically.

**A desk sign-in fails:** desk sign-ins are local and never use the internet. Wrong password: the supervisor resets a receptionist's; the supervisor's own: the owner resets it (Staff). The owner's own, after a change on the phone: sign in online with the new one.

**The desk app won't start on the UB40 PC:**

- "VCRUNTIME140… was not found": install the VC++ Redistributable (x64).
- A missing DLL: the Release folder wasn't copied whole; copy it again.
- "Made by a newer version of the app": an older build was started on newer data; run the go-live build.

**Going back completely** (before real guests only): close the app, move `%APPDATA%\com.lodging\lodging_pos` aside (`docs/release.md`, "Handover"), start again from step 4 with a new install code. On the production project, run the cloud reset in `docs/release.md` first: never connect a second fresh desk to a project that already has an owner.

**After real guests have been recorded, never reset anything.** The desk and its backups hold every record; call me.

## Pointers to the dev project still in the repo

Found with `git grep` on `main`:

| Where | What | What to do |
|---|---|---|
| `supabase/.temp/` (9 files, **committed by mistake** in PR #30) | The CLI's link to the **dev** project: `project-ref` `ptbsemrznqrggxpfbbhn`, `linked-project.json`, `pooler-url` (no password). Not a secret, but anyone cloning got their CLI linked to dev. | Untracked with this runbook (`git rm -r --cached`, `supabase/.temp/` in `.gitignore`; history not rewritten). Each PC keeps its own local link. |
| `lodging_pos/docs/sync.md` lines 20 and 67 | Called the dev project **the** project, and gave its region as eu-central-1; the dev project is in **eu-west-1** (its connection host is `aws-0-eu-west-1.pooler.supabase.com`). | Fixed with this runbook: dev is named as dev, its region corrected, and production points here. |
| `lodging_pos/secrets.json` (untracked, this PC only) | The dev URL and anon key; every build that names it talks to dev. | Keep it for development; production builds name `secrets.prod.json` (step 3). |
| This PC's CLI link (`supabase/.temp/project-ref`) | Points at dev now; at production while doing step 2. | Re-link to dev after step 2 (shown there). |

Nothing in the app code, tests, CI or `supabase/config.toml` names a project: CI runs a local Supabase, and the apps get their project only from the `secrets*.json` file named at build time.
