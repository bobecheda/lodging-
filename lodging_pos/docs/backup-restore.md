# Daily local backup and restore

The desk PC keeps its own copies of the database, so a corrupted file, a bad upgrade or a deleted file never loses the lodging's records. A local copy does **not** protect against a dead disk or a stolen PC: the second folder (a USB drive or external disk) helps until cloud sync arrives in sprint 2, which makes the cloud the off-site copy.

## What happens

| When | What |
|---|---|
| The app starts | Once the database check has passed (`schema_check.dart`), if today (Nairobi) has no backup yet, one is taken. A file that fails the check is never backed up as if it were good. |
| Every hour the app is open | The same check, for a desk that stays on for days. |
| A shift is closed | One more backup straight away, so the day's takings are in a copy. |
| The owner taps **Back up now** | One more backup (`manageBackups`). |

Backups run in the background, one at a time (a request made while one runs waits, then takes its own), and never block the desk or need anyone signed in. Only the Windows desk takes them.

Each backup:

1. `VACUUM INTO` a `.partial` file in the main folder: a consistent copy of the open database, including anything still in the WAL.
2. Checks the copy, attached to the open database for a moment: `PRAGMA integrity_check` must say `ok` and `user_version` must equal this build's schema version.
3. Renames it to `lodging_pos-YYYY-MM-DD-HHMM.sqlite` (Nairobi time). A failed copy is deleted and never replaces a good one.
4. Prunes the folder: every backup from today and yesterday is kept, and the latest of each day for 30 days; anything older is deleted. Files that aren't backups are never touched.
5. Copies the backup to the second folder, if one is set (`.partial`, then renamed), and prunes it the same way. If the folder isn't there (the USB drive unplugged), the copy is skipped; the main backup still counts.
6. Audits it: `backup.create` (file, size, reason `daily` | `shift_close` | `manual`, second copy `copied` | `skipped` | `failed` | `none`), or `backup.failed` (reason and error). The user is the signed-in one, or none for an automatic backup.

## Where

- **Main folder:** `%APPDATA%\com.lodging\lodging_pos\backups` (the app support folder, next to `lodging_pos.sqlite`; the exact path is on the Backups card, with **Open folder**). It is outside Documents on purpose, so Windows doesn't upload it to OneDrive.
- **Second folder (optional):** chosen by the owner on the Backups card (Prices and settings), e.g. `E:\Sunrise Lodge backups` on a USB drive. Stored in the `backup_second_folder` setting (empty: none).

Backups hold the same data as the live database: guests' names, phones and ID numbers, and password hashes. Keep the USB drive locked away.

## What people see

- **Backups card** (Prices and settings, owner only): last backup ("Today 07:02 · 1.8 MB · checked"), the folder with Open folder, Back up now, the reason if the last backup failed, and the second folder (Choose / Change / Remove) with a quiet note about its last copy, e.g. "Second copy skipped: USB drive not found. Main backup OK."
- **Sidebar chip** (everyone): only when the last main backup failed, or yesterday and today have no backup: "Backup failed · last Sun 18 Oct" / "Backup overdue · last Sun 18 Oct". The owner's tap opens the Backups card. A skipped or failed second copy never shows here.

## Restore

There is no restore button yet (sprint 2 adds restoring from the cloud). To restore a local backup:

1. Close the app on the desk PC.
2. Open the database folder (`%APPDATA%\com.lodging\lodging_pos`; the Backups card's Open folder shows the `backups` folder inside it).
3. Rename `lodging_pos.sqlite` to `lodging_pos.sqlite.before-restore-YYYYMMDD` (never delete it). Rename `lodging_pos.sqlite-wal` and `lodging_pos.sqlite-shm` the same way if they are there.
4. Copy the chosen backup (e.g. `backups\lodging_pos-2026-10-20-0702.sqlite`, or from the USB drive) into the folder and rename the copy to `lodging_pos.sqlite`.
5. Start the app. It checks the file as on every start; an older backup is upgraded first (with its own `.v<old>.bak` copy).
6. Sign in and check the bed board, the last receipts and the open shift. Everything after the backup's time must be entered again from paper receipts.

The automated test `test/features/backup/data/backup_service_test.dart` restores a backup this way (opens it as the app's database) and checks that the schema matches and the stays, payments, receipt counter and audit log came through.

## Go-live checklist

- [ ] **Restore rehearsal on the desk PC:** take a backup, restore it with the steps above, and check the bed board and receipts. Then restore the real file back.
- [ ] **A Windows password on every account** on the desk PC.
- [ ] **BitLocker or device encryption on**, if this edition of Windows has it (Settings → Privacy & security → Device encryption, or BitLocker in Windows Pro).
- [ ] **A second folder set** on a USB drive or external disk, and the drive kept locked away when not plugged in.
- [ ] The Backups card shows a backup from today after the first day's work.
