# Daily local backup and restore

The desk PC keeps its own copies of the database, so a corrupted file, a bad upgrade or a deleted file never loses the lodging's records. A local copy does **not** protect against a dead disk or a stolen PC: the second folder (a USB drive or external disk) helps until cloud sync arrives in sprint 2, which makes the cloud the off-site copy.

## What happens

| When | What |
|---|---|
| The app starts | Once the database check has passed (`schema_check.dart`), if today (Nairobi) has no backup yet, one is taken. A file that fails the check is never backed up as if it were good. |
| Every hour the app is open | The same check, for a desk that stays on for days. |
| A shift is closed | One more backup straight away, so the day's takings are in a copy. |
| The supervisor taps **Back up now** | One more backup (`manageBackups`). |

Backups run in the background, one at a time (a request made while one runs waits, then takes its own), and never block the desk or need anyone signed in. Only the Windows desk takes them.

Each backup:

1. `VACUUM INTO` a `.partial` file in the main folder: a consistent copy of the open database, including anything still in the WAL.
2. Checks the copy, attached to the open database for a moment: `PRAGMA integrity_check` must say `ok` and `user_version` must equal this build's schema version.
3. Renames it to `lodging_pos-YYYY-MM-DD-HHMM.sqlite` (Nairobi time). A failed copy is deleted and never replaces a good one.
4. Prunes the folder: every backup from today and yesterday is kept, and the latest of each day for 30 days; anything older is deleted. Files that aren't backups are never touched.
5. Copies the backup to the second folder, if one is set (`.partial`, then renamed), and prunes it the same way. If the folder isn't there (the USB drive unplugged), the copy is skipped; the main backup still counts.
6. Audits it: `backup.create` (file, size, reason `daily` | `shift_close` | `manual`, second copy `copied` | `skipped` | `failed` | `none`), or `backup.failed` (reason and error). The user is the signed-in one, or none for an automatic backup.
7. Writes the **high-water mark**, `lodging_pos.mark.json` next to the database: the backup's name and time, the build that took it, and what the checked copy holds (schema version, the number of stays, payments and audit entries, the last receipt number, the time of the last audit entry). It is written whole (`.partial`, then renamed). A mark that can't be written never fails the backup; the next one writes it again.

## Startup checks

Before the desk opens its database, `main()` runs the startup checks (`core/database/desk_startup.dart` for the rules, `database_files_native.dart` for the file work; story/desk-db-guards, after the 23 Nov 2026 USB incident). They read the files without changing them; a refused database is never opened, so nothing can write to it.

| Check | When it refuses | What the screen says (it always names this app's version, commit and schema, and the file's side) |
|---|---|---|
| **Lock** (`lodging_pos.lock`) | Another copy of the app already has this data folder open. Windows frees the lock when that copy ends, even after a crash. | "The desk is already open on this PC", with the other copy's path and version. **Check again** once it's closed. |
| **Missing file** | `lodging_pos.sqlite` is gone, but backups, pre-upgrade copies, reset folders or a mark show there was one. Only a folder with none of them is a first run. | "Database missing — restore from backup", with the last backup's figures and **Open the data folder**. Restore below, then **Check again**. Never a silent first run. |
| **Newer schema** | The file's schema is newer than this build knows. | "This app is older than the database": e.g. "This database is v12, last opened by desk 1.2.0 (build 4). This app is desk 1.1.0 (build 3), database v11." |
| **Build stamp** | A newer build has opened this file (`sync_state` `desk.build`, raised at every start, never lowered), even at the same schema. Development builds share one build number, so switching branches never trips it; release builds bump it. | The same screen. |
| **High-water mark** | The file holds less than the last backup: an older schema, fewer stays, payments or audit entries, a lower last receipt number, or an earlier last audit entry. Stays, payments and audit entries are never deleted (the triggers refuse it), so on a real desk these never go down. | "This database looks older than the last backup", with both sides' figures. Only the owner may accept it (below). |

Then, in release builds only, **where the app runs from**: from a removable drive (Windows' `GetDriveTypeW`), or from another folder than the install folder recorded at the first run (`desk.install_path`), the desk shows a warning before sign-in. The supervisor or the owner may carry on with their username and password (`acceptUnusualStart`, audited as `desk.unusual_start` with the path); for another fixed folder they may also make it the install folder. A receptionist can't; they close the window and use the usual shortcut. A removable drive is never recorded as the install folder.

The version line ("Desk 1.1.0 (build 3) · a1b2c3d · database v11") is on the sign-in screen, at the foot of the user menu and the drawer, and on every refusal. The commit comes from `--dart-define=APP_COMMIT=…` at build time (`docs/release.md`); without it the line says "dev".

The **debug reset** (a file made by an older development build) asks for `RESET` to be typed, copies the file and checks the copy, then moves the file, its side files and the mark into `reset-YYYYMMDD-HHMMSS` next to it. Nothing is deleted. Release builds never offer it.

`test/policy/live_file_ops_test.dart` fails the build if anything but `database_files_native.dart` names the live file or the files beside it, or if anything but that file, the backups and saved receipts renames, copies or deletes files.

## Where

- **Main folder:** `%APPDATA%\com.lodging\lodging_pos\backups` (the app support folder, next to `lodging_pos.sqlite`; the exact path is on the Backups card, with **Open folder**). It is outside Documents on purpose, so Windows doesn't upload it to OneDrive.
- **Second folder (optional):** chosen by the supervisor on the Backups card (Prices and settings), e.g. `E:\Sunrise Lodge backups` on a USB drive. Stored in the `backup_second_folder` setting (empty: none).

Backups hold the same data as the live database: guests' names, phones and ID numbers, and password hashes. Keep the USB drive locked away.

## What people see

- **Backups card** (Prices and settings, supervisor only): last backup ("Today 07:02 · 1.8 MB · checked"), the folder with Open folder, Back up now, the reason if the last backup failed, and the second folder (Choose / Change / Remove) with a quiet note about its last copy, e.g. "Second copy skipped: USB drive not found. Main backup OK."
- **Sidebar chip** (everyone): only when the last main backup failed, or yesterday and today have no backup: "Backup failed · last Sun 18 Oct" / "Backup overdue · last Sun 18 Oct". The supervisor's tap opens the Backups card. A skipped or failed second copy never shows here.

## Restore

There is no restore button yet (sprint 2 adds restoring from the cloud). To restore a local backup:

1. Close the app on the desk PC.
2. Open the database folder (`%APPDATA%\com.lodging\lodging_pos`; the Backups card's Open folder shows the `backups` folder inside it).
3. Rename `lodging_pos.sqlite` to `lodging_pos.sqlite.before-restore-YYYYMMDD` (never delete it). Rename `lodging_pos.sqlite-wal` and `lodging_pos.sqlite-shm` the same way if they are there.
4. Copy the chosen backup (e.g. `backups\lodging_pos-2026-10-20-0702.sqlite`, or from the USB drive) into the folder and rename the copy to `lodging_pos.sqlite`.
5. Start the app. It checks the file as on every start. A backup older than the high-water mark is refused as "older than the last backup" (next section); once accepted, an older backup is upgraded first (with its own `.v<old>.bak` copy).
6. Sign in and check the bed board, the last receipts and the open shift. Everything after the backup's time must be entered again from paper receipts.

## Restoring an older backup

Restoring is always deliberate. A backup older than the last one taken is refused at start until **the owner** accepts it on the refusal screen (`acceptRestore`, owner only; if the owner isn't at the desk, it waits). Nobody else can.

**What goes wrong without a rule (analysed 24 Nov 2026).** The receipt counter (`receipt_counter`) is local-only and never synced, so it goes back with the file: the next sale reissues a number already printed (e.g. R-000051 again). In the cloud, `payments.receipt_number` and `refunds.receipt_number` are unique, as are one active stay per bed, one open shift per device, a guest's ID and an M-Pesa code. Old outbox rows replay harmlessly (insert-only tables do nothing on a conflict; other tables keep the newer cloud row), but the first new payment with a reused number is refused, and **a refused row stops the push queue** (only voids are held aside). A new check-in on a bed the cloud still sees occupied, or a new shift while a lost one is still open in the cloud, jams it the same way. The pull cursor goes back too: rows already on the desk are skipped, but an owner's decision about a refund the desk lost clashes and stops the pull. The desk never pulls its own tables back, so stays, payments and drawer counts made after the backup would stay in the cloud and never return to the desk: two truths, and a wrong drawer ledger. On a desk that never synced there is no jam, but receipt numbers printed after the backup would be reused on paper.

**The rule.**

1. **Never accept a restore when the cloud has anything newer from this desk.** Every desk write has an audit row (single write path), so the test is: the cloud's newest `audit_log` row with this desk's `device_id` must not be newer than the restored file's newest audit entry. The check reads the cloud with the owner's own sign-in (the owner can already read every synced table), so it needs no cloud migration. Offline, a desk that has synced can't accept a restore; it waits for the internet. Raising the receipt counter alone would not be enough: the active-stay, open-shift, guest and M-Pesa conflicts and the lost drawer ledger would remain.
2. **When the cloud has nothing newer, or the desk never connected,** the owner also types the number on the last receipt printed. Before the first sale, the counter moves past the highest of: the restored file's next number and last receipt, the last backup's last receipt (from the mark), the cloud's highest number for this device, and the paper receipt. The accept is audited as `database.restore_accepted` (the restored and the previous figures, the counter before and after).
3. **The pull cursor is left as it is.** Rule 1 guarantees nothing in the cloud refers to rows the desk lost.

**What is built.**

- **A desk that never connected** (story/desk-db-guards): the owner's password is checked against the restored file (read-only); then the paper receipt number; then the mark is reset to the restored file with the restore pending. Once the file opens, before anyone signs in, the counter is raised and `database.restore_accepted` audited.
- **A desk that has synced** (the restored file says so, or the desk still holds its cloud key; story/restore-cloud-check): the owner's password is checked by the cloud instead, by signing in as the owner with the email the file knows (`sync_state` `owner_email`; the screen asks for it when the file doesn't). The desk reads what the cloud holds from its own `device_id` (`Cloud.deskInCloud`: the newest `audit_log` entry and the highest receipt number in `payments` and `refunds`), then signs the owner out again.
  - Anything newer than the restored file's last audit entry refuses the restore: "The cloud has newer records from this desk …". Nothing is written; this is a support call.
  - Otherwise the counter floor also passes the cloud's highest number for this desk, and the audit says `cloud_checked: true`.
  - Offline, a build without cloud keys, or an account that isn't the owner's: the restore waits, and nothing is written.

The cloud check needs no cloud migration: the owner can already read every synced table.

The automated test `test/features/backup/data/backup_service_test.dart` restores a backup this way (opens it as the app's database) and checks that the schema matches and the stays, payments, receipt counter and audit log came through.

## Go-live checklist

- [ ] **Restore rehearsal, before the desk connects to the cloud:** take a backup, restore an earlier one with the steps above, see it refused as older, accept it as the owner with the last paper receipt, and check the bed board, the receipts and that the next receipt number comes after the paper one. Then restore the real file back (it isn't older than the mark, so it opens as it is).
- [ ] **A Windows password on every account** on the desk PC.
- [ ] **BitLocker or device encryption on**, if this edition of Windows has it (Settings → Privacy & security → Device encryption, or BitLocker in Windows Pro).
- [ ] **A second folder set** on a USB drive or external disk, and the drive kept locked away when not plugged in.
- [ ] The Backups card shows a backup from today after the first day's work.
