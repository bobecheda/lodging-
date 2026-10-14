# lodging_pos

Front desk + admin system for a lodging that charges **per bed, per 12-hour block**.
One Flutter codebase: **Windows** build = front desk (offline-first), **Android/web** builds = admin (online).

- Product requirements and acceptance criteria: `docs/prd.md`
- Database schema: `docs/schema.md`
- Business rules (BR-1 to BR-12), statuses, worked examples: the `lodging-rules` skill in `.claude/skills/lodging-rules/` — load it before any task that touches stays, payments, pricing, beds, shifts or occupancy.

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

Features: `auth`, `shifts`, `setup`, `guests`, `bed_board`, `stays`, `payments`, `receipts`, `housekeeping`, later `inventory`, `expenses`, `reports`, `dashboard`.
`test/` mirrors `lib/`. Create a folder only when writing its first real file.

## Conventions (non-negotiable)

- **Money** is whole KES stored as `int`. Never `double`.
- **Time** is stored in UTC, displayed in Africa/Nairobi. Never call `DateTime.now()` outside `core/clock`; inject the `Clock` so tests control time.
- **IDs** are UUID v4 strings on every synced table. Every synced table has `id`, `created_at`, `updated_at`, `device_id`.
- **Single write path.** Repositories never write to drift directly; every insert/update goes through `AuditWriter.writeWithAudit(action:, userId:, body:)` in `core/audit`. In one transaction, for each synced row the body writes with `w.insert` / `w.update`, it also writes an `audit_log` row (that row's before/after, tagged with the action) and `outbox` rows for both. Build rows with the companion's `.insert(...)` so business fields are checked at compile time. `id` defaults to a new UUID (pass your own to link rows in the same transaction). The writer stamps `created_at`, `updated_at` and `device_id` on insert, and `updated_at` and `device_id` on update (never `created_at`); their client defaults throw, so an insert that bypasses the writer fails. Every audit row of one call shares an `operation_id`. Audit and outbox rows are written as each row is written, so nested calls keep write order; await every write (un-awaited ones are awaited before commit, and the handle throws once the call returns). Triggers reject direct updates that don't move `updated_at` and any delete of stays, payments, charges, voids or audit_log. Use `w.now` for business timestamps. Events that change no rows (`user.login`, `user.login_failed`) use `recordEvent`. If any part fails, nothing is saved.
- **Audit actions** are named `entity.verb`: `stay.check_in`, `stay.renew`, `stay.check_out`, `payment.create`, `void.create`, `shift.open`, `shift.close`, `bed.mark_clean`, `housekeeping.assign`, `price.update`, `room.create`, `bed.create`, `user.create`, `user.disable`, `user.change_password`, `user.login`, `user.login_failed`, `settings.update`. One call may record several actions (`w.insert(..., action:)`), all under one `operation_id`.
- **Append-only:** no update or delete code exists for `audit_log`. Stays and payments are never edited or deleted by users; corrections are `voids` rows (admin only).
- **Occupancy is never stored.** Derive Available / Occupied / Overstay from active stays + clock (see the skill).
- **Business rules live in `domain/`** as pure functions with unit tests. Screens never calculate prices, times or statuses.
- Every screen and service must work with **no internet**.
- UI text in English, amounts shown as `KES 1,000`.

## Workflow

- One story per branch: `story/fd-4-check-in`. Story IDs (FD-x, AD-x) and acceptance criteria are in `docs/prd.md`.
- For domain rules, write the tests first.
- Before saying a story is done, check the Definition of Done:
  1. acceptance criteria pass
  2. works with the network off
  3. writes audit entries for its actions
  4. `flutter analyze` clean and `flutter test` passes
  5. runs in the Windows build
- Schema changes go through a new drift migration (bump `schemaVersion`); never edit an applied migration.
- Commit messages: use the `commit-style` skill.

## Commands

```
flutter pub get
dart run build_runner build                 # drift + riverpod codegen
dart run drift_dev make-migrations          # after bumping schemaVersion
flutter analyze
flutter test
flutter run -d windows
flutter build windows --release
```

## Current sprint

Sprint 1 (14–27 Oct 2026): a receptionist can run a full stay offline — login and shifts (FD-1), admin setup on the desk app (AD-1 to AD-4), guests (FD-3), bed board (FD-2), check-in (FD-4), payment (FD-5), receipt (FD-6), checkout (FD-8). Not in sprint 1: sync, admin phone app, overstay renewal UI, shift close, voids UI, inventory, expenses, reports.
