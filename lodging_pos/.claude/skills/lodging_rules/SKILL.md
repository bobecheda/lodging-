---
name: lodging-rules
description: Business rules for lodging_pos — per-bed 12-hour block pricing, overstay and grace period, renewals, bed statuses, payments, shifts and voids. Use before writing or changing any code or test that touches stays, payments, pricing, beds, occupancy, housekeeping or shifts.
---

# Lodging business rules

These rules are the product. They live as pure Dart functions in `lib/features/<feature>/domain/`, each covered by unit tests, and are never re-implemented in screens or repositories. When a requirement seems to conflict with a rule here, stop and ask; do not pick one silently.

## Rules

| ID | Rule | Where enforced |
|---|---|---|
| BR-1 | Price is per bed, per block of `block_hours` (12) from check-in. 24 h = 2 blocks. Day and night blocks cost the same. | `stays/domain` |
| BR-2 | Category prices (seed): VIP 1000, Deluxe 700, Comfort 600, Normal 500. Only admin changes them. | `setup` + role guard |
| BR-3 | `price_per_block` is copied from the category at check-in and reused for every renewal of that stay. Price changes affect new check-ins only. | `stays/domain` |
| BR-4 | One guest per bed. Strangers may share a 2-bed room. One guest may pay for both beds: two stays, one payment. | DB partial unique index + `stays/domain` |
| BR-5 | A bed can be let only if it is active, Available and `clean`. It becomes Occupied only when the check-in transaction (stay + payment + charges) commits. | `stays/domain` + transaction |
| BR-6 | Grace = `grace_minutes` (60). A bed is Overstay when now > `paid_until` + grace and the stay is active. | `bed_board/domain` |
| BR-7 | A renewal's `period_start` = the stay's current `paid_until` (not the time it is entered). | `stays/domain` |
| BR-8 | No refunds. Early checkout forfeits unused blocks. | `stays/domain` |
| BR-9 | Checkout → bed `not_cleaned`. Only completing a housekeeping task sets `clean`. | `stays`, `housekeeping` |
| BR-10 | An M-Pesa code can be used once across all payments. Required for `paybill`, null for `cash`. | DB unique + `payments/domain` |
| BR-11 | Stays, payments, charges and audit entries are never edited or deleted by users. Admin corrects with a `voids` row and a reason. Voided payments are excluded from totals. | repositories + role guard |
| BR-12 | Every payment belongs to an open shift. No open shift → no check-in, renewal or payment. | `shifts/domain` |

## Calculations

```dart
// All times UTC. blockHours and graceMinutes come from settings.
int totalDue(int blocks, int pricePerBlock) => blocks * pricePerBlock;

DateTime periodEnd(DateTime periodStart, int blocks, int blockHours) =>
    periodStart.add(Duration(hours: blocks * blockHours));

// Check-in: periodStart = checkInAt. Renewal: periodStart = stay.paidUntil (BR-7).

enum Occupancy { available, occupied, overstay }

Occupancy occupancyOf({Stay? activeStay, required DateTime now, required int graceMinutes}) {
  if (activeStay == null) return Occupancy.available;
  final overstayAt = activeStay.paidUntil.add(Duration(minutes: graceMinutes));
  return now.isAfter(overstayAt) ? Occupancy.overstay : Occupancy.occupied;
}

bool canLet(Bed bed, Occupancy occ) =>
    bed.isActive && occ == Occupancy.available && bed.cleanliness == Cleanliness.clean;

// A room is not_cleaned if any of its active beds is not_cleaned.
```

Occupancy is never stored. It is always derived from the active stay and the `Clock`.

## Statuses

| Event | Occupancy after | Cleanliness after |
|---|---|---|
| Check-in committed | Occupied | unchanged (must be clean before) |
| now > paid_until + grace | Overstay | unchanged |
| Renewal | Occupied (paid_until moves forward) | unchanged |
| Checkout | Available | not_cleaned |
| Housekeeping task completed | unchanged | clean |
| Stay voided by admin | Available | not_cleaned |

## Required test cases

Every one of these must exist as a unit test in the matching `domain/` test file:

1. Check-in 22:00, 1 block → paid_until 10:00 next day; total = price.
2. Check-in 10:00, 2 blocks → paid_until 10:00 next day; total = 2 × price.
3. 20 blocks prepaid → paid_until = check-in + 240 h.
4. paid_until 10:00, now 10:59 → Occupied. now 11:00 → Occupied. now 11:00:01 → Overstay.
5. Renewal entered at 10:40 with paid_until 10:00, 1 block → period 10:00→22:00.
6. Category price changes 700 → 800 after check-in → renewal still charged 700.
7. Both beds of a 2-bed room for one guest → two stays, one payment, amount = sum of both charges.
8. Bed not_cleaned → cannot let. Bed inactive → cannot let. Bed with active stay → cannot let.
9. Paybill without code → rejected. Reused code → rejected. Cash with code → rejected.
10. Payment without an open shift → rejected.
11. Early checkout after 1 of 3 paid blocks → no refund, bed Available + not_cleaned.
12. Voided payment → excluded from shift expected totals and revenue.

## Receipts

- Number format `R-000041` (prefix from settings, 6 digits, gap-free per device via `receipt_counter`, incremented in the payment transaction).
- Header: lodging name only. Body: receipt number, guest, room and bed, category, blocks, period start → end, amount, method, M-Pesa code, receptionist, date/time in Nairobi time.
- Reprints after the first are marked "Copy" (`print_count`).

## Guests

- Required: full name, phone. Optional: ID type (`national_id`, `passport`, `alien_id`) and ID number.
- If an ID number is entered, ID type is required and the pair must be unique.
- Search by phone or ID number, as the user types.
