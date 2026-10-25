# Release, install and handover

How the owner's app (Android) and the desk (Windows) are built, installed and tested, how a demo is frozen, and how everything is reset before installing at the lodging.

## The owner's app (Android)

The owner's app is installed by hand from a release APK. It isn't on the Play Store before go-live, and the web build is compiled in CI but not hosted.

### The toolchain (once)

1. Android Studio (or the command-line tools) with the Android SDK installed.
2. Accept the SDK licenses, then check that "Android toolchain" is ticked:

   ```bash
   flutter doctor --android-licenses
   ```

   ```bash
   flutter doctor
   ```

3. On the phone: Settings → About phone → tap "Build number" 7 times; then Developer options → turn on **USB debugging**. Plug it in and accept "Allow USB debugging" on the phone.

### What a release build contains

- **Internet:** `android/app/src/main/AndroidManifest.xml` asks for `android.permission.INTERNET` (the main manifest, so release builds have it; the debug-only manifest isn't used for release).
- **The cloud's address and key:** read at build time from `secrets.json` (`--dart-define-from-file=secrets.json`) and compiled in. A build without it shows "This build has no cloud set up" on the sign-in screen.
- **R8:** Flutter shrinks every release build (minify and resource shrinking). `flutter_secure_storage` (the owner's sign-in and the install id) ships no R8 rules and encrypts with Google Tink, so `android/app/proguard-rules.pro` keeps both. The proof is on the phone: still signed in after the app is closed and reopened (checklist below). `supabase_flutter` is Dart; its Android plugins (app links, URL launcher, shared preferences) bring their own rules.
- **Android 7.0 (API 24) or later:** `flutter_secure_storage` needs it.

### The upload key (once)

The APK is signed with an upload key that only you hold. **Lose it and the installed app can't be updated**: a new key means uninstalling the app (and signing in again) on every phone.

1. Create it with `keytool` (it comes with the JDK; Android Studio has one in `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`). Run it outside the repo, e.g. in `%USERPROFILE%\keys`:

   ```bash
   keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   It asks for a keystore password, your name and organisation, and a key password (press Enter to use the same one).

2. **Back it up in two places**, both away from this PC, e.g. an encrypted USB drive kept at home and a password manager that stores files. Back up the `.jks` file **and** its passwords together. Test that a backup opens:

   ```bash
   keytool -list -keystore upload-keystore.jks
   ```

3. Create `lodging_pos/android/key.properties` (never committed: `.gitignore` blocks `key.properties`, `*.jks` and `*.keystore`):

   ```properties
   storePassword=<the keystore password>
   keyPassword=<the key password>
   keyAlias=upload
   storeFile=C:/Users/<you>/keys/upload-keystore.jks
   ```

   Use forward slashes in `storeFile` (a backslash is an escape in this file). Don't put the key or this file in the repo, a chat or a ticket.

### Building, checking and installing

From `lodging_pos`:

```bash
flutter build apk --release -t lib/main_owner.dart --dart-define-from-file=secrets.json
```

The APK is `build\app\outputs\flutter-apk\app-release.apk`. Check it is signed with your key (the owner shown must be your name, not "Android Debug"):

```bash
keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk
```

Install it over USB (`adb` is in `%LOCALAPPDATA%\Android\Sdk\platform-tools`; the phone must be listed as `device`):

```bash
adb devices
```

```bash
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

If it says `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, a build signed with another key (e.g. a debug one) is on the phone: uninstall it first, then install again (the owner signs in again):

```bash
adb uninstall com.lodging.lodging_pos
```

To update later, raise `version` in `pubspec.yaml`, build again and install over it with `adb install -r`; the owner stays signed in.

Without `android/key.properties` the release build is signed with the debug key (`android/app/build.gradle.kts`). That is what CI builds (job `owner-app-build`, which also compiles the web build and keeps nothing). **Never install a debug-signed APK on the owner's phone**: the next properly signed one won't install over it.

### Phone test checklist

On the phone, with the desk connected to the same cloud:

1. The app opens on "Owner sign in" (not "This build has no cloud set up").
2. Sign in with the owner's email and desk password: Today loads, the header says "Updated just now" and the desk's state.
3. **Close the app completely (swipe it away) and open it again: still signed in, no sign-in screen.** (This is the R8 / secure storage check.)
4. Today's figures match the desk's Today.
5. A refund requested at the desk shows under Needs your attention within a minute (pull down to refresh); approve it on the phone; the desk shows it under Refunds → To pay after its next pull.
6. Prices: change a price on the phone; the desk's Prices shows it after its next pull. Change the same category at the desk with the old price still showing: the desk says "… was changed to KES … on the phone".
7. Money, Beds and More → Shifts, Audit trail and Staff open and show the desk's data; no guest phone or ID number appears anywhere.
8. Airplane mode: the header says "Offline · showing …"; approving says it needs the internet. Turn it off: pull down, "Updated just now".
9. More → Change password, then sign in at the desk: the old password gets "Your password was changed on your phone…", the new one works (online). Change it back the same way if needed.
10. More → Sign out: back to sign-in; reopening the app stays signed out.

## The desk on another PC (Windows)

### What to copy

Build on this PC (not while the app runs from `flutter run` on it; the release folder is separate from the debug one):

```bash
flutter build windows --release --dart-define-from-file=secrets.json
```

Copy **the whole folder** `lodging_pos\build\windows\x64\runner\Release` to the other PC, e.g. to `C:\UB40\Desk`, and make a shortcut to `lodging_pos.exe`. It holds `lodging_pos.exe`, `flutter_windows.dll`, `sqlite3.dll`, `pdfium.dll`, the `*_plugin.dll` files, `native_assets.json` and the `data` folder; the app needs all of them, side by side, and nothing else.

### The VC++ runtime

The other PC needs the **Microsoft Visual C++ 2015–2022 Redistributable (x64)**: download `vc_redist.x64.exe` from Microsoft (https://aka.ms/vs/17/release/vc_redist.x64.exe) and install it once. Without it, Windows says `MSVCP140.dll`, `VCRUNTIME140.dll` or `VCRUNTIME140_1.dll` "was not found". Most PCs already have it (Programs and Features lists "Microsoft Visual C++ 2015-2022 Redistributable (x64)").

### Where the desk keeps its data

Per Windows user, in `%APPDATA%\com.lodging\lodging_pos\` (e.g. `C:\Users\Reception\AppData\Roaming\com.lodging\lodging_pos\`):

- `lodging_pos.sqlite` (with `-wal` and `-shm` while it runs): the database.
- `lodging_pos.sqlite.v<N>.bak`: the copy kept before each upgrade (newest two).
- `backups\`: the daily backups (`docs/backup-restore.md`); a second copy goes to the folder set on the Backups card.
- `flutter_secure_storage.dat`: the desk's cloud secret, encrypted with a key in **that Windows user's** Credential Manager. Run the desk under one Windows user only (`docs/sync.md`).

### First run on a new PC (checklist)

1. VC++ Redistributable (x64) installed; the Release folder copied whole; the shortcut opens the app.
2. Windows date, time and time zone (Nairobi, UTC+3) are right and set automatically.
3. First run: "Create the owner's account", then the lodging's setup; sign in as the supervisor and add rooms, beds and receptionists.
4. A receptionist opens a shift, checks a guest in, takes a payment, prints the receipt (the printer is set up in Windows first), and closes the shift.
5. Backups: "Back up now" on the Backups card, then check `%APPDATA%\com.lodging\lodging_pos\backups` has today's file; set the second backup folder if a USB drive is used.
6. Unplug the network: everything above still works.
7. **Connecting to the cloud:** only one desk per lodging connects, with a fresh install code. A second test PC must **not** connect to the cloud project the main desk uses: its first run created a different owner (the project has one owner and refuses another), and a database copied from another desk would carry that desk's device id. Test a second PC offline, or against a project of its own.

## Freezing the demo

After the phone and second-PC checklists pass, with this branch merged and CI green on `main`:

```bash
git checkout main
```

```bash
git pull --ff-only
```

```bash
git tag -a v0.9-demo -m "Demo build for the owner meeting"
```

```bash
git push origin v0.9-demo
```

Build the demo APK and Windows folder from the tag (`git checkout v0.9-demo`). No changes go into the demo after the tag; fixes wait for the next tag.

## Handover: resetting before installing at the lodging

Everything made while testing (stays, payments, staff, the test owner, the desks' cloud accounts) must go before the lodging starts. **Recommended:** a fresh production Supabase project, created in the hardening week with the owner's real email (`docs/sync.md`, "Environments"); then only the desk and the phone need resetting. If the test project is reused instead, reset the cloud too.

### The cloud (only if reusing a project)

In the Supabase dashboard, **check the project name first**, then run this in the SQL Editor. It removes every row of the lodging's data, the desks' and the owner's cloud accounts, and the install codes; it can't be undone.

```sql
begin;
-- The desks' and the owner's sign-ins, remembered before their rows go.
create temp table reset_accounts on commit drop as
  select auth_user_id as id from app_private.devices
  union
  select auth_user_id from app_private.owner;

truncate table
  public.audit_log, public.voids, public.refund_decisions,
  public.price_decisions, public.owner_password_changes, public.refunds,
  public.stay_charges, public.payments, public.stays, public.shifts,
  public.housekeeping_tasks, public.inventory_movements,
  public.inventory_items, public.expenses, public.price_requests,
  public.guests, public.beds, public.rooms, public.bed_categories,
  public.housekeepers, public.settings, public.users, public.desk_status,
  app_private.devices, app_private.install_codes, app_private.owner,
  app_private.price_changes, app_private.connect_attempts
  cascade;

delete from auth.users where id in (select id from reset_accounts);
alter sequence public.sync_seq restart;
commit;
```

Check it is empty (both counts 0):

```sql
select (select count(*) from public.users) as users,
       (select count(*) from app_private.devices) as desks;
```

Then make the lodging's install code (shown once, valid 7 days):

```sql
select app_private.new_install_code();
```

`TRUNCATE` is used because the cloud refuses row deletes on its append-only tables (audit, payments, stays, …) by design.

### The desk (not SQL)

The desk refuses deletes on purpose (its audit trail and money rows are append-only), so it is reset by moving its data folder away, not by SQL. With the desk app **closed**, in PowerShell on the desk PC:

```powershell
Move-Item "$env:APPDATA\com.lodging\lodging_pos" "$env:USERPROFILE\Desktop\lodging_pos-test-archive"
```

That takes the database, its upgrade copies, the backups and the desk's cloud secret together. Keep the archive until the lodging has run for a week, then delete it. The next start is a first run ("Create the owner's account"); then connect the desk with the new install code (`docs/sync.md`, "Setting up the cloud"). If a second backup folder was set, empty it too.

### The phone

Uninstall the test app (or Sign out in More), then install the release APK from the demo tag and sign in with the owner's real account.

## Before go-live (hardening)

- Show the app version on More's account card ("Android app 1.0"; needs `package_info_plus`).
