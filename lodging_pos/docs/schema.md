# Database schema — lodging_pos

Local database: SQLite via drift (front desk). Cloud mirror: PostgreSQL on Supabase (sprint 2).

## Common rules

- Every synced table has: `id` TEXT (UUID v4, primary key), `created_at`, `updated_at`, `device_id` TEXT. The one exception is `settings`, whose primary key is `key` (see below).
- All timestamps are UTC. All money columns are INTEGER whole KES.
- `outbox`, `receipt_counter` and `device` are local only and never synced. `audit_log` is append-only.
- Ownership for sync: the **desk** owns operational tables, the **admin** owns setup tables, `voids`, `expenses` and `inventory_items`. A row is only ever written by its owner.

## Relationships

```
bed_categories 1──* beds *──1 rooms
                    beds 1──* stays *──1 guests
                   stays 1──* stay_charges *──1 payments *──1 shifts *──1 users
                   voids ──► payments | stays
                    beds 1──* housekeeping_tasks *──1 housekeepers
         inventory_items 1──* inventory_movements
```

## Setup tables (admin owns)

### users
| Column | Type | Notes |
|---|---|---|
| full_name | TEXT | required |
| username | TEXT | UNIQUE |
| password_hash | TEXT | bcrypt |
| role | TEXT | `admin` \| `receptionist` |
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

Seed keys: `lodging_name` = `""` (filled by the first-run setup screen), `block_hours` = `12`, `grace_minutes` = `60`, `receipt_prefix` = `R`.

### bed_categories
| Column | Type | Notes |
|---|---|---|
| name | TEXT | UNIQUE |
| price_per_block | INT | KES |
| sort_order | INT | |
| is_active | BOOL | |

Seed: VIP 1000, Deluxe 700, Comfort 600, Normal 500, with fixed UUIDs so the cloud can seed the same rows.

Seed rows are written in `onCreate` with no `audit_log` or `outbox` rows. No user is seeded: when `users` is empty the desk shows a first-run setup screen that creates the admin (FD-1).

### rooms
| Column | Type | Notes |
|---|---|---|
| room_number | TEXT | UNIQUE |
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

UNIQUE(room_id, label). Max 2 active beds per room (enforced in repository).

### housekeepers
| Column | Type | Notes |
|---|---|---|
| full_name | TEXT | |
| phone | TEXT | optional |
| is_active | BOOL | |

## Front desk tables (desk owns)

### guests
| Column | Type | Notes |
|---|---|---|
| full_name | TEXT | required |
| phone | TEXT | required, INDEX |
| id_type | TEXT | optional: `national_id` \| `passport` \| `alien_id` |
| id_number | TEXT | optional |

Partial UNIQUE(id_type, id_number) WHERE id_number IS NOT NULL. If `id_number` is set, `id_type` is required.

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
| status | TEXT | `open` \| `closed` |

At most one open shift per device.

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

Partial UNIQUE(bed_id) WHERE status = 'active' — one guest per bed, enforced by the database.

### payments (also the receipt)
| Column | Type | Notes |
|---|---|---|
| receipt_number | TEXT | UNIQUE, e.g. `R-000041` (gap-free per device) |
| shift_id | TEXT → shifts | must be open |
| received_by | TEXT → users | |
| received_at | DATETIME | |
| amount | INT | = sum of its `stay_charges.amount` |
| method | TEXT | `cash` \| `paybill` |
| mpesa_code | TEXT | UNIQUE; required for `paybill`, null for `cash` |
| print_count | INT | reprints after the first are marked "Copy" |

### stay_charges
| Column | Type | Notes |
|---|---|---|
| stay_id | TEXT → stays | |
| payment_id | TEXT → payments | one payment can cover both beds of a room |
| kind | TEXT | `check_in` \| `renewal` |
| blocks | INT | ≥ 1 |
| price_per_block | INT | locked from the stay's first charge |
| amount | INT | blocks × price_per_block |
| period_start | DATETIME | check-in time, or previous `period_end` for renewals |
| period_end | DATETIME | period_start + blocks × block_hours |

### housekeeping_tasks
| Column | Type | Notes |
|---|---|---|
| bed_id | TEXT → beds | |
| housekeeper_id | TEXT → housekeepers | |
| assigned_by | TEXT → users | |
| assigned_at | DATETIME | |
| completed_at | DATETIME | null until done |
| completed_by | TEXT → users | receptionist who marked it done |

## Admin-owned records

### voids
| Column | Type | Notes |
|---|---|---|
| target_type | TEXT | `payment` \| `stay` |
| target_id | TEXT | |
| reason | TEXT | required |
| voided_by | TEXT → users | admin only |
| voided_at | DATETIME | |

### expenses (sprint 3)
`category` (laundry \| utilities \| wages \| supplies \| repairs \| other), `amount` INT, `spent_on` DATE, `note`, `recorded_by` → users.

### inventory_items (sprint 3)
`name` UNIQUE, `unit`, `low_stock_level` INT, `is_active`.

### inventory_movements (sprint 3, desk owns)
`item_id` → inventory_items, `direction` (in \| out), `quantity` INT > 0, `reason`, `recorded_by` → users. Stock out may not take an item below zero.

## System tables

### audit_log (append-only, synced)
| Column | Type | Notes |
|---|---|---|
| at | DATETIME | |
| user_id | TEXT → users | null for failed logins |
| device_id | TEXT | |
| action | TEXT | `entity.verb`, e.g. `stay.check_in` |
| entity | TEXT | table name |
| entity_id | TEXT | |
| before_json | TEXT | null on create |
| after_json | TEXT | |

### outbox (local only)
| Column | Type | Notes |
|---|---|---|
| seq | INT | autoincrement primary key — send in this order |
| table_name | TEXT | |
| row_id | TEXT | |
| payload_json | TEXT | full row after the change |
| created_at | DATETIME | |
| attempts | INT | |
| last_error | TEXT | |
| sent_at | DATETIME | null until synced |

### receipt_counter (local only)
`device_id` primary key, `next_number` INT. Incremented inside the same transaction as the payment.

> **TODO (sprint 2, sync):** if the database is deleted or the PC replaced, the new `device_id` starts `receipt_counter` at 1 and `R-000001` would collide with receipts already in the cloud. On a fresh install, sync must seed `next_number` from the cloud's highest receipt number before the first payment.

### device (local only, never synced)
| Column | Type | Notes |
|---|---|---|
| device_id | TEXT | primary key, UUID v4 generated in `onCreate` |
| created_at | DATETIME | |

Exactly one row. Its `device_id` is stamped on every synced row written by this install.

## Worked example

Guest checks in 22:00 on bed 3A (Deluxe, 700) for 1 block, renews at 10:40, then leaves.

| Step | Rows written |
|---|---|
| Check-in, Paybill | `stays` paid_until 10:00 · `payments` R-000041, 700, paybill, code · `stay_charges` check_in, 1 × 700, 22:00→10:00 |
| Renew at 10:40 | `payments` R-000042, 700 · `stay_charges` renewal, 1 × 700, 10:00→22:00 · `stays` paid_until 22:00 |
| Checkout | `stays` closed, checked_out_at · `beds` not_cleaned |

Each step also writes `audit_log` and `outbox` rows in the same transaction.
