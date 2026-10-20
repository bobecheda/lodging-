# lodging_pos

Front desk + admin system for a lodging that charges **per bed, per night, checkout 10:00**.
One Flutter codebase: **Windows** build = front desk (offline-first), **Android/web** builds = admin (online).

- Product requirements and acceptance criteria: `docs/prd.md`
- Database schema: `docs/schema.md`
- Business rules (BR-1 to BR-13), refund lifecycle, statuses, required test cases: the `lodging-rules` skill in `.claude/skills/lodging-rules/` — load it before any task that touches stays, payments, refunds, pricing, beds, shifts, occupancy or access control.

## Stack

- Flutter (stable), Dart 3
- State: `flutter_riverpod` · Navigation: `go_router`
- Local database: `drift` + `drift_flutter` (`sqlite3` 3.x bundles SQLite via build hooks; `sqlite3_flutter_libs` is obsolete)
- Passwords: `bcrypt` · IDs: `uuid` · Receipts/reports: `pdf` + `printing`
- Cloud (sprint 2): Supabase (PostgreSQL, auth, row-level security)

## Project structure

`flutter create` owns the platform folders (`android/`, `windows/`, `web/`); don't restructure them. All app code is organised feature-first inside `lib/`:

```
lib/
├── main.dart
├── app/                 # router, theme, shell, role guard
├── core/
│   ├── database/        # drift tables, database.dart, migrations
│   ├── audit/           # writeWithAudit: business rows + audit_log + outbox in ONE transaction
│   ├── sync/            # sprint 2: push outbox, pull settings
│   ├── clock/           # Clock service — the only source of "now"
│   ├── auth/            # session, password hashing
│   └── money/           # KES formatting
└── features/<feature>/
    ├── domain/          # pure Dart: models + business rules. No Flutter, no database imports.
    ├── data/            # repositories: read/write via core/database and core/audit
    └── presentation/    # screens, widgets, Riverpod providers
```

Features: `auth`, `shifts`, `setup`, `guests`, `bed_board`, `stays`, `payments`, `receipts`, `housekeeping`, `backup`, later `inventory`, `expenses`, `reports`, `dashboard`.
`test/` mirrors `lib/`. Create a folder only when writing its first real file.

## Conventions (non-negotiable)

- **Money** is whole KES stored as `int`. Never `double`.
- **Time** is stored in UTC, displayed in Africa/Nairobi. Never call `DateTime.now()` outside `core/clock`; inject the `Clock` so tests control time.
- **IDs** are UUID v4 strings on every synced table. Every synced table has `id`, `created_at`, `updated_at`, `device_id`.
- **Single write path.** Repositories never write to drift directly; every insert/update goes through `AuditWriter.writeWithAudit(action:, userId:, body:)` in `core/audit`. In one transaction, for each synced row the body writes with `w.insert` / `w.update`, it also writes an `audit_log` row (that row's before/after, tagged with the action) and `outbox` rows for both. Build rows with the companion's `.insert(...)` so business fields are checked at compile time. `id` defaults to a new UUID (pass your own to link rows in the same transaction). The writer stamps `created_at`, `updated_at` and `device_id` on insert, and `updated_at` and `device_id` on update (never `created_at`); their client defaults throw, so an insert that bypasses the writer fails. Every audit row of one call shares an `operation_id`. Audit and outbox rows are written as each row is written, so nested calls keep write order; await every write (un-awaited ones are awaited before commit, and the handle throws once the call returns). Triggers reject direct updates that don't move `updated_at` and any delete of stays, payments, charges, refunds, refund decisions, voids or audit_log. Use `w.now` for business timestamps. Events that change no rows (`user.login`, `user.login_failed`) use `recordEvent`. If any part fails, nothing is saved.
- **Audit actions** are named `entity.verb`: `stay.check_in`, `stay.extend`, `stay.late_charge`, `stay.check_out`, `payment.create`, `refund.request`, `refund.approve`, `refund.reject`, `refund.pay`, `void.create`, `shift.open`, `shift.close`, `bed.mark_clean`, `housekeeping.assign`, `price.update`, `room.create`, `bed.create`, `user.create`, `user.disable`, `user.change_password`, `user.login`, `user.login_failed`, `user.auto_lock`, `user.lock`, `user.reset_password`, `settings.update`, `room.update`, `room.deactivate`, `room.reactivate`, `bed.update`, `bed.deactivate`, `bed.reactivate`, `category.create`, `category.update`, `housekeeper.create`, `housekeeper.update`, `housekeeper.deactivate`, `housekeeper.reactivate`, `user.enable`, `guest.create`, `guest.update`, `payment.print` (a receipt printed or saved; later ones say COPY), `housekeeping.reassign` (the open task's housekeeper changed; the audit keeps old and new), `housekeeping.cancel` (closing a bed or room cancels its open cleaning task; the bed stays not cleaned), `backup.create` and `backup.failed` (daily local backups, through `recordEvent`). One call may record several actions (`w.insert(..., action:)`), all under one `operation_id`.
- **Append-only:** no update or delete code exists for `audit_log`. Stays, payments, charges, refunds and refund decisions are never edited or deleted by users; corrections are `voids` rows (`voidRecords` permission).
- **Refunds are calculated by the system** (`stays/domain/stay_rules.dart`: nights not yet started × the stay's locked price). No screen lets anyone type or change a refund amount. A refund is requested at early checkout, approved or rejected by a user with `approveRefund`, then paid out once from an open shift (`features/refunds/domain/refund.dart`).
- **Payment methods** are `cash` | `paybill` for payments and refund payouts alike (`PaymentMethod`); screens, receipts and reports label `paybill` as "M-Pesa" (`PaymentMethod.label`).
- **Occupancy is never stored.** Derive Available / Occupied / Overstay from active stays + clock (see the skill).
- **Business rules live in `domain/`** as pure functions with unit tests. Screens never calculate prices, times or statuses.
- **Permissions (BR-13):** every protected action is checked through the one permission map in `core/auth/permissions.dart` (`Permission` enum → allowed roles) with `can(user, p)` / `requirePermission(user, p)` (throws `NotPermitted`). Never compare roles (`role == Role.admin`) anywhere else; `test/policy/no_role_checks_test.dart` fails the build otherwise. Writes take the acting `UserAccount` and call `requirePermission`; routes need theirs too (`Routes.permissions` in `app/gate.dart`, setup routes fail closed) and nav items declare one (`NavItem.permission`). Hiding a screen is never the only lock. A new role (e.g. supervisor) is added by editing only the map.
- Every screen and service must work with **no internet**.
- UI text in English, amounts shown as `KES 1,000`; dates `Thu 15 Oct`, times 24-hour `07:02` (`core/clock/nairobi.dart`).
- **Phones** use one rule in `core/contacts/phone.dart`: spaces and dashes ignored, `+254`/`254` become `0`, only 07… and 01…, stored as 10 digits. Guests may also give an international number (`+` and 8–15 digits, stored as `+` and digits; the Kenyan rule is tried first); housekeepers are Kenyan-only. Lists show phones masked (`0722 ••• 310`, `+2567 ••• 678`); only a selected guest's card shows the full number. ID numbers always show masked (`••••3921`, `core/contacts/id_number.dart`). Audit entries keep only the compact masks (`0722•••310`, `••••3921`).
- **Design system** (spec: `docs/design.md`, artboards in `docs/design/`): raw colours, font sizes and font families live **only** in `lib/app/theme/` (`LodgingColors`, `LodgingType`, `Space`/`Radii`/`Sizes`); everything else reads them from the theme. `test/policy/no_raw_style_test.dart` fails the build otherwise. Fonts (Manrope, IBM Plex Mono) are bundled in `assets/fonts/` with their sources recorded in its README. Shared widgets live in `lib/app/widgets/` (buttons, `LabeledField`, `MoneyInput`, `SegmentedChoice`, `NightStepper`, `Note`, `StatusBadge`, `BedStatusTile`); working screens go inside `DeskShell` (`lib/app/shell/`), and each story adds its sidebar entry to `deskNavItems`. Every screen must render at **1366×768** without overflow (`test/app/screen_layout_test.dart`).
- **Settings** are read through `SettingsRepository` (`core/settings`). Every default lives in one map, `settingDefaults` in `core/settings/setting_defaults.dart`; the v1 seed writes it, any upgrade inserts keys still missing, and the reader falls back to it, so a new setting only needs an entry there.
- **Inactivity lock:** after `idle_lock_minutes` (default 10, range 1–60, one validator in `auth/domain/idle_lock.dart`) without a click, scroll, key press or mouse movement, the session signs out to the login screen (`user.auto_lock`); the sidebar's Lock screen button does the same at once (`user.lock`). Either way the shift stays open.
- **Shifts:** a receptionist must open (or continue) their shift after signing in. An admin works without one (`workWithoutShift`) and is never sent to the shift screen, but a payment always goes into the user's **own** open shift, so an admin taking one opens a shift first: check-in's "Open shift" goes to `/shift?then=…` and returns there (`Routes.shiftThen`, `redirectFor(returnTo:)`).
- **Widget tests and the database:** inside `tester.runAsync`, never write and then read again while the app is running: the write wakes the app's watched queries, which take the database lock in fake time, and the next read waits forever. Set up data (e.g. open the shift) before pumping the app.
- **Daily local backup** (`features/backup`, `docs/backup-restore.md`): on the Windows desk only, once the database check passes at start, then hourly if today (Nairobi) has none, after every shift close and on "Back up now" (`manageBackups`). `VACUUM INTO` a `.partial` file, checked (`integrity_check`, `user_version`), renamed to `lodging_pos-YYYY-MM-DD-HHMM.sqlite` in `<app support>\backups`; kept: today and yesterday in full, then the latest per day for 30 days; copied to the optional `backup_second_folder` (a missing drive is only noted on the Backups card). One at a time, in the background. The sidebar chip shows only for a failed main backup or none for yesterday and today. Tests set `env.backupFolder` (a temp folder) to turn backups on; widget tests wait for their real file I/O with `settleRealIo`.
- **Secrets are never written in code, tests or committed config.** Keys (e.g. the Supabase URL and anon key in sprint 2) are passed at build time with `--dart-define-from-file=secrets.json` from an untracked file and read with `String.fromEnvironment`. The repo-root `.gitignore` blocks `.env`, `*.env` and `secrets*.json`. Test passwords are made-up values for in-memory databases; `.gitguardian.yaml` excludes `lodging_pos/test/**` from secret scanning.

## Workflow

- One story per branch: `story/fd-4-check-in`. Story IDs (FD-x, AD-x) and acceptance criteria are in `docs/prd.md`.
- For domain rules, write the tests first.
- Before saying a story is done, check the Definition of Done:
  1. acceptance criteria pass
  2. works with the network off
  3. writes audit entries for its actions
  4. `flutter analyze` clean and `flutter test` passes
  5. runs in the Windows build
- **Schema v1 is frozen as of 16 Oct 2026. Every schema change is a numbered drift migration with a migration test. Never edit an applied migration.** The steps:
  1. Change the tables and bump `schemaVersion` in `database.dart`.
  2. Run `dart run drift_dev make-migrations`. It snapshots the new version in `drift_schemas/`, writes `database.steps.dart` and the test helpers in `test/drift/app_database/generated/`, and creates `test/drift/app_database/migration_test.dart` once.
  3. Add the generated step to `_upgrade` (`stepByStep(from1To2: …)`).
  4. Fill the migration test with real v1 rows and check they survive the upgrade. Its `AppDatabase(...)` calls need `clock:`.
  5. A new NOT NULL column gets a default or a backfill in its step. A new setting key needs only its entry in `settingDefaults`: after any upgrade, missing keys are inserted at their default (`insertMissingSettings`).
- **Column names must not clash with drift Table members** (e.g. no `table_name`, `row_id`, `primary_key`, `unique_keys`, `without_row_id`, `is_strict`, `custom_constraints`). Drift's generated schema code names its getters after the SQL columns, and a clash stops `database.steps.dart` from compiling.
- **Every upgrade** (`AppDatabase._upgrade`, details in `docs/schema.md`): the file is first copied to `lodging_pos.sqlite.v<old>.bak` (release builds too, newest two kept); then, with foreign keys off, the steps, a `PRAGMA foreign_key_check` (any report fails and undoes the migration) and the new version run in one transaction. The database always opens in WAL with `synchronous = FULL`. Schema is at **v5** (stay charges keep their category; stays keep their room number and bed label; cleaning tasks can be cancelled; a shift keeps its first count, close note and closer, and never changes once closed).
- **Database check at startup** (`core/database/schema_check.dart`): after any migration, the app compares the database file with the schema this build creates (SQL text normalized: whitespace, `"` quotes, spaces at `( ) ,`).
  - A debug build shows a "made by an older build" screen with a reset button. Reset renames the file to `lodging_pos.sqlite.bak-…` (never deleted) and starts fresh.
  - A release build shows an error, leaves the data untouched, and never offers a reset.
  - A file from a newer app version is refused.
- Commit messages: use the `commit-style` skill.

## Commands

```
flutter pub get
dart run build_runner build                 # drift + riverpod codegen
dart run drift_dev make-migrations          # after bumping schemaVersion (v1 is frozen)
flutter analyze
flutter test
flutter run -d windows
flutter build windows --release
dart format --output=none --set-exit-if-changed .   # what CI checks
```

## CI

GitHub Actions (`.github/workflows/ci.yml`), Flutter pinned to the local version (**3.47.5**; change it there and locally together).

- **`CI / checks`** (Ubuntu, 15 min) runs on every pull request and every push to `main`, and is required to merge into `main`: `flutter pub get --enforce-lockfile`, `build_runner` then `git diff --exit-code` (committed generated code must be current), `drift_dev make-migrations` then no changed or new files (a schema change needs its numbered migration and snapshot), `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test --timeout 120s`. Run these locally before pushing; a red check blocks the merge.
- **`windows-build`** (Windows, 30 min) runs on pushes to `main` and on demand: `flutter build windows --release`, kept as a zip artifact for 14 days. Not required.
- GitGuardian runs separately, unchanged.
- `.drift` files are checked out as CRLF on every OS (`.gitattributes`) because drift copies trigger SQL text, line endings included, into the schema snapshots. Don't change this rule without regenerating and reviewing all snapshots.
- If a golden test ever fails on Ubuntu only because of font rendering, tag it `golden`, skip that tag in `checks` and run it in `windows-build`; never move `checks` to Windows for that.
- Locally, don't run `flutter build windows --debug` while the app may be running from `flutter run`: they share the Debug folder. Use `--release` to check a build.

## Current sprint

Sprint 1 (14–27 Oct 2026): a receptionist can run a full stay offline — login and shifts (FD-1), admin setup on the desk app (AD-1 to AD-4), guests (FD-3), bed board (FD-2), check-in (FD-4), payment (FD-5), receipt (FD-6), checkout (FD-8, refund requests only), housekeeping (FD-9: assign and mark clean), then CI, shift close (FD-11) and extend (FD-7: in the bed panel and on the overstay bar; during an overstay at least the nights already started, counted like a late checkout). Then the daily local backup (Backups card, sidebar chip, `docs/backup-restore.md`). Not in sprint 1: sync, admin phone app, refund approval, payout and REFUND receipt (AD-7, sprint 2), voids UI, inventory, expenses, reports.

AD-7 (refund approval, payout and REFUND receipt) is one of the first stories of sprint 2.
