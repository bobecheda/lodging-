# Database schema — lodging_pos

Local database: SQLite via drift (front desk). Cloud mirror: PostgreSQL on Supabase (sprint 2).

## Versions

**Schema v1 is frozen as of 16 Oct 2026** (snapshot: `drift_schemas/app_database/drift_schema_v1.json`). Every schema change is a numbered drift migration with a migration test; an applied migration is never edited. New NOT NULL columns get a default or a backfill in their migration step, and setting keys added later are inserted at their default after the upgrade. Column names must not clash with drift Table members (e.g. no `table_name`), or drift's generated migration code won't compile.

| Version | Date | Change |
|---|---|---|
| v1 | 16 Oct 2026 | First frozen schema |
| v2 | 17 Oct 2026 (FD-4) | `stay_charges.category_id` and `category_name`: the bed's category at check-in, kept with the price. Existing charges are filled from their stay's bed by rebuilding the table (an UPDATE would trip the charge triggers); the rebuild is local, not audited or queued |
| v5 | 19 Oct 2026 (FD-11) | `shifts.first_count`, `close_note` (≤ 200) and `closed_by`; shifts already closed get `first_count = counted_cash` and `closed_by = user_id`; trigger `shifts_closed_final` refuses any change to a closed shift |
| v6 | 21 Oct 2026 (roles) | `users.role` CHECK becomes `owner` \| `supervisor` \| `receptionist`; the rebuild copies `admin` users as `supervisor` (no UPDATE, timestamps unchanged). Old audit rows keep `"role":"admin"`; sync (sprint 2) must read an unsent outbox payload's `admin` as `supervisor` |
| v4 | 19 Oct 2026 (FD-9) | `housekeeping_tasks.cancelled_at` and `cancelled_by` (empty for existing tasks); the one-open-task index leaves out cancelled tasks; a task can't be both completed and cancelled |
| v3 | 18 Oct 2026 (FD-6) | `stays.room_number` and `bed_label`, as let; existing stays filled from their bed and room by rebuilding the table |

**How an upgrade runs** (`AppDatabase._upgrade`):

1. The file is copied to `lodging_pos.sqlite.v<old>.bak` with `VACUUM INTO` (release builds too). The newest two copies are kept; older ones are deleted.
2. Foreign keys are switched off (a step may rebuild a table others point to), then in **one transaction**: the generated steps, `PRAGMA foreign_key_check` over the whole file, and the new `user_version`. If the check reports anything, the migration fails and is undone; the file stays at its old version.
3. On every open: WAL journal with `synchronous = FULL` (each commit is on disk before it returns, so a power cut can't lose a committed payment), and foreign keys on.
4. The startup check then compares the file with what this build creates. It compares each table, index and trigger's SQL with whitespace collapsed, `"` quotes stripped and no space next to `(`, `)` or `,` (a rebuilt table is spelt slightly differently from a fresh one). If that ever causes trouble again, compare `PRAGMA table_info` / `index_list` / `foreign_key_list` instead.

## Common rules

- Every synced table has: `id` TEXT (UUID v4, primary key), `created_at`, `updated_at`, `device_id` TEXT. The one exception is `settings`, whose primary key is `key` (see below).
- `id` defaults to a new UUID. `created_at`, `updated_at` and `device_id` are stamped by `writeWithAudit` (on update: `updated_at` and `device_id`, never `created_at`). Their drift client defaults throw, so a row inserted any other way fails (the seed passes them explicitly).
- Database triggers (`triggers.drift`) back this up: an UPDATE of a synced table that leaves `updated_at` unchanged is aborted, `stays`, `payments`, `stay_charges`, `refunds`, `refund_decisions` and `voids` rows cannot be deleted, and `audit_log` and `refund_decisions` cannot be updated. Triggers also enforce the refund lifecycle and M-Pesa codes across tables (see `refunds`).
- All timestamps are UTC. All money columns are INTEGER whole KES.
- `outbox`, `receipt_counter` and `device` are local only and never synced. `audit_log` is append-only.
- Ownership for sync: the **desk** owns operational tables (including `refunds`), the **admin side** owns setup tables, `voids`, `refund_decisions`, `expenses` and `inventory_items` (the supervisor's and the owner's records). Each row has a single writer. In sprint 1 the admin signs in on the desk PC, so admin-owned rows (e.g. a refund decision) are written there too; sync (sprint 2) must push them from the desk as well as from the phone.
- Payment and refund methods are `cash` | `paybill` everywhere; screens and reports label `paybill` as "M-Pesa".

## Relationships

```
bed_categories 1──* beds *──1 rooms
                    beds 1──* stays *──1 guests
                   stays 1──* stay_charges *──1 payments *──1 shifts *──1 users
                   stays 1──0..1 refunds 1──0..1 refund_decisions
                 refunds *──0..1 shifts   (the shift that paid it out)
                   voids ──► payments | stays | refunds
                    beds 1──* housekeeping_tasks *──1 housekeepers
         inventory_items 1──* inventory_movements
```

## Setup tables (supervisor owns)

### users
| Column | Type | Notes |
|---|---|---|
| full_name | TEXT | required |
| username | TEXT | UNIQUE; stored trimmed and lowercase (CHECK `username = lower(trim(username))`), so uniqueness is case-insensitive |
| password_hash | TEXT | bcrypt |
| role | TEXT | `owner` \| `supervisor` \| `receptionist` (v6; `admin` before). What each may do is only in the permission map |
| is_active | BOOL | disabled users cannot log in |
| must_change_password | BOOL | set on create and reset |

### settings
| Column | Type | Notes |
|---|---|---|
| key | TEXT | primary key |
| value | TEXT | |
| updated_by | TEXT → users | null for seeded values |
| created_at | DATETIME | |
| updated_at | DATETIME | |
| device_id | TEXT | |

The one exception to the `id` rule: `key` is the primary key and sync upserts by `key`.

Seed keys: `lodging_name` = `""` (filled by the first-run setup screen), `checkout_time` = `10:00` (`HH:MM`, Nairobi; range 06:00–14:00), `grace_minutes` = `60` (0–180; a change applies at once to every guest, since overstay is derived), `receipt_prefix` = `R` (1–4 letters, stored uppercase), `idle_lock_minutes` = `10` (1–60; a stored value outside that falls back to 10), `backup_second_folder` = `""` (the optional second folder each daily backup is also copied to, e.g. a USB drive; a path on the desk PC, set on the Backups card; sprint 2 sync must keep it on the device). `lodging_name` is required, at most 60 characters. AD-3 edits them; each changed key is one `settings.update` audit row with its old and new value. There is no early-arrival cut-off: every arrival checks out at `checkout_time` on the next calendar day. Defaults come from one map in code (`settingDefaults`); the settings reader falls back to it for any key missing from the database.

### bed_categories
| Column | Type | Notes |
|---|---|---|
| name | TEXT | UNIQUE ignoring case (`COLLATE NOCASE`); stored trimmed, 1–30 characters (CHECK) |
| price_per_night | INT | whole KES 1–100,000 (CHECK) |
| sort_order | INT | new categories go last |
| is_active | BOOL | a closed category can't be chosen for a bed |

A category can't be closed while active beds use it, counting beds in rooms closed for repairs (reopening the room would let them). Categories are never renamed or deleted. Price changes (`price.update`) apply to new check-ins only.

Seed: VIP 1000, Deluxe 700, Comfort 600, Normal 500, with fixed UUIDs so the cloud can seed the same rows.

Seed rows are written in `onCreate` with no `audit_log` or `outbox` rows. No user is seeded: when `users` is empty the desk shows a first-run setup screen that creates the supervisor (FD-1; sprint 2: the owner first).

### rooms
| Column | Type | Notes |
|---|---|---|
| room_number | TEXT | UNIQUE; stored trimmed and uppercase (CHECK `room_number = upper(trim(room_number))`) |
| floor | TEXT | optional |
| notes | TEXT | optional |
| is_active | BOOL | inactive rooms leave the bed board, history kept |

### beds
| Column | Type | Notes |
|---|---|---|
| room_id | TEXT → rooms | |
| label | TEXT | `A` \| `B` |
| category_id | TEXT → bed_categories | |
| cleanliness | TEXT | `clean` \| `not_cleaned` |
| is_active | BOOL | |

UNIQUE(room_id, label), so a room has at most 2 beds, active or not. A bed under repair is deactivated and later reactivated, never replaced by a new row. New beds start `clean`; a bed or room reactivated after repairs comes back `not_cleaned`. A bed or room with an active stay can't be deactivated, and an active room keeps 1 or 2 active beds (its last active bed can't be deactivated; close the room instead).

### housekeepers
| Column | Type | Notes |
|---|---|---|
| full_name | TEXT | trimmed, 1–60 characters |
| phone | TEXT | optional; Kenyan 07… or 01…, stored as 10 digits (`core/contacts/phone.dart`) |
| is_active | BOOL | inactive housekeepers can't be picked for cleaning |

## Front desk tables (desk owns)

### guests
| Column | Type | Notes |
|---|---|---|
| full_name | TEXT | required, trimmed, 1–80 characters |
| phone | TEXT | required, INDEX, COLLATE NOCASE (prefix search uses the index). Kenyan `07…`/`01…` as 10 digits, or international `+` and 8–15 digits |
| id_type | TEXT | optional: `national_id` \| `passport` \| `alien_id` |
| id_number | TEXT | optional, INDEX, COLLATE NOCASE. Stored without spaces, in capitals: National ID 6–9 digits; Passport and Alien ID 6–12 letters and digits |

Partial UNIQUE(id_type, id_number) WHERE id_number IS NOT NULL, ignoring case: the same ID (type + number) can't belong to two guests, but the same digits under another type can. If `id_number` is set, `id_type` is required. Phones may be shared (families). Guests are found by phone or ID prefix, never by name; the Guests screen lists the 30 most recently registered or corrected (`updated_at`).

### shifts
| Column | Type | Notes |
|---|---|---|
| user_id | TEXT → users | |
| opened_at | DATETIME | |
| opening_float | INT | |
| closed_at | DATETIME | null while open |
| expected_cash | INT | set on close |
| expected_paybill | INT | set on close |
| counted_cash | INT | set on close |
| variance | INT | counted − expected |
| first_count | INT | v5: the first, blind count; `counted_cash` is the final one after any recount |
| close_note | TEXT | v5: ≤ 200 characters; the app requires it when variance ≠ 0 |
| closed_by | TEXT → users | v5: who closed it (a supervisor may close someone else's, `closeOtherShifts`) |
| status | TEXT | `open` \| `closed` |

At most one open shift per device. A closed shift must have `closed_at`, `expected_cash`, `expected_paybill`, `counted_cash` and `variance`, with `variance = counted_cash − expected_cash`. Since v5 it also has `first_count` and `closed_by`, and trigger `shifts_closed_final` refuses any change to it: a closed shift can't be reopened (FD-11). Closing is one `shift.close` write; its audit entry keeps both counts.

### stays
| Column | Type | Notes |
|---|---|---|
| guest_id | TEXT → guests | |
| bed_id | TEXT → beds | |
| check_in_at | DATETIME | |
| paid_until | DATETIME | = latest `stay_charges.period_end` |
| checked_out_at | DATETIME | null while active |
| status | TEXT | `active` \| `closed` |
| checked_in_by | TEXT → users | |
| checked_out_by | TEXT → users | |
| room_number | TEXT | v3: the room's number at check-in, so a receipt survives a renumbering |
| bed_label | TEXT | v3: `A` \| `B`, as let |

Partial UNIQUE(bed_id) WHERE status = 'active' — one guest per bed, enforced by the database. `checked_out_at` and `checked_out_by` are set exactly when `status = 'closed'`.

### payments (also the receipt)
| Column | Type | Notes |
|---|---|---|
| receipt_number | TEXT | UNIQUE, e.g. `R-000041` (gap-free per device) |
| shift_id | TEXT → shifts | must be open |
| received_by | TEXT → users | |
| received_at | DATETIME | |
| amount | INT | = sum of its `stay_charges.amount` |
| method | TEXT | `cash` \| `paybill` |
| mpesa_code | TEXT | UNIQUE (ignoring case), also across refund payouts (trigger); required for `paybill`, null for `cash` |
| print_count | INT | times printed or saved (`payment.print`); the first is the original, every later one says COPY. Viewing on screen or a cancelled print dialog doesn't count |

### stay_charges
| Column | Type | Notes |
|---|---|---|
| stay_id | TEXT → stays | |
| payment_id | TEXT → payments | one payment can cover both beds of a room |
| kind | TEXT | `check_in` \| `extension` \| `late_checkout` |
| nights | INT | ≥ 1 |
| price_per_night | INT | copied from the category at check-in; every later charge of the stay reuses it |
| amount | INT | nights × price_per_night |
| period_start | DATETIME | check-in time, or the stay's `paid_until` for extensions and late-checkout charges |
| period_end | DATETIME | check-in: 10:00 on the day after arrival + (nights − 1) days; otherwise `period_start` + nights (Nairobi calendar days) |
| category_id | TEXT → bed_categories | v2: the bed's category at check-in; every later charge of the stay reuses it. Reports group by it |
| category_name | TEXT | v2: that category's name at check-in, so a receipt never changes |

A late-checkout charge moves `stays.paid_until` like an extension, so `paid_until` is always the latest `period_end`.

A check-in (FD-4) writes, in one transaction: the new guest if any (`guest.create`), one stay and one check-in charge per bed (`stay.check_in`), one payment for all of them (`payment.create`) into the user's own open shift, and the next `receipt_counter` number.

A checkout (FD-8) writes, in one transaction and in the user's own open shift: for a late checkout, a `late_checkout` charge with its own payment and receipt (`stay.late_charge`, `payment.create`) that moves `paid_until`; for an early one, a `refunds` row as a **request** (`refund.request`); then the stay closed and the bed `not_cleaned` (`stay.check_out`). The terms are worked out again at the moment of saving and must match what the panel showed.

An extension (FD-7) writes, in one transaction and in the user's own open shift: one payment with the next receipt number (`payment.create`), one `extension` charge for one bed from the old `paid_until`, n nights at the stay's check-in price (`stay.extend`), and the stay's new `paid_until` (`stay.extend`). It is refused if `paid_until` changed since the panel showed it, or if more nights have started meanwhile than were chosen (the minimum during an overstay is the late-checkout night count at that moment).

### refunds
A refund of prepaid nights not yet started (BR-8), created as a **request** in the early-checkout transaction that also closes the stay. Its status is derived, never stored: no decision → `requested`; decision `rejected` → `rejected`; decision `approved` and no payout → `approved`; payout set → `paid`.

| Column | Type | Notes |
|---|---|---|
| stay_id | TEXT → stays | UNIQUE: one refund per stay |
| nights | INT | ≥ 1, nights not yet started |
| price_per_night | INT | the stay's locked price |
| amount | INT | nights × price_per_night; calculated, never typed |
| requested_by | TEXT → users | |
| requested_at | DATETIME | |
| method | TEXT | payout: `cash` \| `paybill`, null until paid |
| mpesa_code | TEXT | payout: UNIQUE (ignoring case), also across payments (trigger); required for `paybill`, null for `cash` |
| shift_id | TEXT → shifts | payout: the open shift that paid it; that shift's totals count the refund |
| paid_by | TEXT → users | payout |
| paid_at | DATETIME | payout |
| receipt_number | TEXT | payout: UNIQUE, from `receipt_counter` |
| print_count | INT | reprints after the first are marked "Copy" |

The payout columns are null together until paid, then set together. Triggers: a refund is inserted unpaid; `stay_id`, `nights`, `price_per_night`, `amount`, `requested_by` and `requested_at` never change; the payout can be set only once an `approved` decision exists, and only once (reprints still update `print_count`).

### housekeeping_tasks
| Column | Type | Notes |
|---|---|---|
| bed_id | TEXT → beds | |
| housekeeper_id | TEXT → housekeepers | |
| assigned_by | TEXT → users | |
| assigned_at | DATETIME | |
| completed_at | DATETIME | null until done |
| completed_by | TEXT → users | receptionist who marked it done |
| cancelled_at | DATETIME | v4: null unless the bed or room was closed with the task open |
| cancelled_by | TEXT → users | v4: who closed it |

Partial UNIQUE(bed_id) WHERE completed_at IS NULL AND cancelled_at IS NULL: at most one open task per bed. `completed_at` and `completed_by` are set together, and so are `cancelled_at` and `cancelled_by` (v4); a task is never both. Completing a task (`bed.mark_clean`) is the only way a bed becomes clean (BR-9). Closing a bed or room cancels its open task (`housekeeping.cancel`) and leaves the bed not cleaned. Reassigning changes `housekeeper_id` on the open task (`housekeeping.reassign`). "Already cleaned" creates and completes a task in one operation (`housekeeping.assign` + `bed.mark_clean`).

## Supervisor and owner records

### voids
| Column | Type | Notes |
|---|---|---|
| target_type | TEXT | `payment` \| `stay` \| `refund` (voids a refund's payout) |
| target_id | TEXT | |
| reason | TEXT | required |
| voided_by | TEXT → users | needs `voidRecords` (supervisor) |
| voided_at | DATETIME | |

Voided payments and refund payouts are excluded from shift totals and revenue.

### refund_decisions
| Column | Type | Notes |
|---|---|---|
| refund_id | TEXT → refunds | UNIQUE: one decision per refund |
| decision | TEXT | `approved` \| `rejected` |
| note | TEXT | required (non-blank) when rejected |
| decided_by | TEXT → users | needs `approveRefund` (owner); never the refund's `requested_by` for an approval |
| decided_at | DATETIME | |

Written once, never updated or deleted. It holds no amount, so the approver cannot change it.

### expenses (sprint 3)
`category` (laundry \| utilities \| wages \| supplies \| repairs \| other), `amount` INT, `spent_on` TEXT `YYYY-MM-DD` (Nairobi date, CHECKed by GLOB), `note`, `recorded_by` → users.

### inventory_items (sprint 3)
`name` UNIQUE, `unit`, `low_stock_level` INT, `is_active`.

### inventory_movements (sprint 3, desk owns)
`item_id` → inventory_items, `direction` (in \| out), `quantity` INT > 0, `reason`, `recorded_by` → users. Stock out may not take an item below zero.

## System tables

### audit_log (append-only, synced)
| Column | Type | Notes |
|---|---|---|
| at | DATETIME | |
| operation_id | TEXT | UUID, INDEX. Same value on every row written by one `writeWithAudit` call; AD-8 groups by it |
| user_id | TEXT → users | null for failed logins |
| device_id | TEXT | |
| action | TEXT | `entity.verb`, e.g. `stay.check_in` |
| entity | TEXT | table name |
| entity_id | TEXT | |
| before_json | TEXT | null on create; on update, only the columns that changed |
| after_json | TEXT | full row on create; on update, only the columns that changed |

Audit JSON redacts `users.password_hash` and guests' `full_name` as `"[redacted]"`, and stores guests' and housekeepers' `phone` masked (`0722•••310`) and guests' `id_number` masked (`••••3921`), before and after, so a change is still visible while personal data stays purgeable. The business row's outbox payload keeps the real values.

### outbox (local only)
| Column | Type | Notes |
|---|---|---|
| seq | INT | autoincrement primary key — send in this order |
| target_table | TEXT | the business table's name |
| target_row_id | TEXT | its primary key |
| payload_json | TEXT | full row after the change |
| created_at | DATETIME | |
| attempts | INT | |
| last_error | TEXT | |
| sent_at | DATETIME | null until synced |

### receipt_counter (local only)
`device_id` primary key, `next_number` INT. Incremented inside the same transaction as the payment or refund payout; both draw from this one counter.

> **TODO (sprint 2, sync):** if the database is deleted or the PC replaced, the new `device_id` starts `receipt_counter` at 1 and `R-000001` would collide with receipts already in the cloud. On a fresh install, sync must seed `next_number` from the cloud's highest receipt number before the first payment.

### device (local only, never synced)
| Column | Type | Notes |
|---|---|---|
| device_id | TEXT | primary key, UUID v4 generated in `onCreate` |
| created_at | DATETIME | |

Exactly one row. Its `device_id` is stamped on every synced row written by this install.

## Backup files

Daily local backups (`docs/backup-restore.md`) are whole copies of the database file, made with `VACUUM INTO` and checked (`integrity_check`, `user_version`) before they count: `lodging_pos-YYYY-MM-DD-HHMM.sqlite` (Nairobi time) in `<app support>\backups`, and in the optional `backup_second_folder`. They need no table: the newest is read from the folder. Each is audited with `recordEvent` (`backup.create`, `backup.failed`, entity `backups`, the file name as id).

## Worked examples

Times are Nairobi. Checkout 10:00, grace 60 minutes, bed 3A (Deluxe, 700).

**One night, extended, then a late checkout.** Check-in Thu 15 Oct 19:00 for 1 night, extend at Fri 11:40, leave Sat 11:30.

| Step | Rows written |
|---|---|
| Check-in, Paybill | `stays` paid_until **Fri 16 Oct 10:00** · `payments` R-000041, 700, paybill, code · `stay_charges` check_in, 1 × 700, Thu 19:00 → Fri 10:00 |
| Extend 1 night at Fri 11:40 (overstay since 11:00) | `payments` R-000042, 700 · `stay_charges` extension, 1 × 700, Fri 10:00 → Sat 10:00 · `stays` paid_until Sat 10:00 |
| Check out Sat 11:30, after grace | `payments` R-000043, 700 · `stay_charges` late_checkout, 1 × 700, Sat 10:00 → Sun 10:00 · `stays` paid_until Sun 10:00, closed, checked_out_at Sat 11:30 · `beds` not_cleaned |

Leaving between Sat 10:00 and 11:00 would have been free.

**Ten nights, early checkout with a refund.** Check-in Thu 15 Oct 19:00 for 10 nights, leave Wed 21 Oct 15:00.

| Step | Rows written |
|---|---|
| Check-in, cash | `stays` paid_until **Sun 25 Oct 10:00** · `payments` R-000044, 7,000, cash · `stay_charges` check_in, 10 × 700 |
| Check out Wed 15:00 | 7 nights used (night 7 began Wed 10:00 and its grace has passed), 3 not started · `stays` closed · `beds` not_cleaned · `refunds` request 3 × 700 = 2,100 |
| Owner approves | `refund_decisions` approved |
| Pay out in cash | `refunds` method cash, shift_id (the open shift), paid_by, paid_at, receipt R-000045 · that shift's cash refunded +2,100, so its expected cash falls by 2,100 |

A rejection instead writes `refund_decisions` rejected with a reason, and the refund is never paid.

Each step also writes, in the same transaction, one `audit_log` row per changed row (all sharing the step's `operation_id`) and `outbox` rows for the business and audit rows.
