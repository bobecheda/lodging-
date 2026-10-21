---
name: lodging-rules
description: Business rules for lodging_pos — per-bed, per-night pricing with a fixed 10:00 checkout the day after arrival, grace period and overstay, extensions, late-checkout charge, owner-approved refunds for unused prepaid nights, bed statuses, payments, shifts, voids and permissions. Use before writing or changing any code or test that touches stays, payments, refunds, pricing, beds, occupancy, housekeeping, shifts or access control.
---

# Lodging business rules

These rules are the product. They live as pure Dart functions in `lib/features/<feature>/domain/`, each covered by unit tests, and are never re-implemented in screens or repositories. When a requirement seems to conflict with a rule here, stop and ask; do not pick one silently.

All wall-clock rules (10:00, dates) are in **Africa/Nairobi** local time. Store UTC; convert with the injected `Clock`/time-zone helper before applying a rule. Nairobi has no daylight saving, but still use calendar-date arithmetic, not "+24 h", so the code is correct by construction. Domain code uses the pure-Dart `ClockTime(hour, minute)` from `core/clock`, never Flutter's `TimeOfDay`.

## Settings used by these rules

| Key | Default | Range |
|---|---|---|
| `checkout_time` | `10:00` | 06:00–14:00 |
| `grace_minutes` | `60` | 0–180 |

There is **no** early-arrival cut-off: the owner confirmed that every arrival, whatever the time, checks out at 10:00 on the following calendar day.

## Rules

| ID | Rule |
|---|---|
| BR-1 | Price is per bed, **per night**. Every night ends at `checkout_time` (10:00). Arrival time never changes the price. |
| BR-1a | **First checkout** = 10:00 on the calendar day **after** the arrival date, for any arrival time (03:00 Thu → Fri 10:00; 23:59 Thu → Fri 10:00; 00:30 Fri → Sat 10:00). |
| BR-2 | Category prices are per night (seed: VIP 1000, Deluxe 700, Comfort 600, Normal 500). Only users with `editPrices` change them directly, at any time: the **owner**. A supervisor asks for a change (`requestPriceChange`, a later story; until then the supervisor's prices are read-only) and the owner approves or rejects it (`decidePriceChange`). Adding and closing categories is the owner's too. |
| BR-3 | `price_per_night` is copied from the category at check-in and reused for every extension, late-checkout charge and refund of that stay. Price changes affect new check-ins only. |
| BR-4 | One guest per bed. Strangers may share a 2-bed room. One guest may pay for both beds: two stays, one payment. |
| BR-5 | A bed can be let only if it is active, Available and `clean`. It becomes Occupied only when the check-in transaction (stay + payment + charges) commits. |
| BR-6 | `paid_until` = first checkout + (nights − 1) days, at 10:00. A bed is **Overstay** when now > `paid_until` + `grace_minutes` and the stay is active. |
| BR-7 | **Extension:** adds n nights from `paid_until`: new `paid_until` = old `paid_until` + n days. Allowed any time the stay is active, including during an overstay. |
| BR-7a | **Late checkout:** checking out after `paid_until` + grace first charges the nights that have started (normally 1), at the stay's price, as a `late_checkout` charge with its own payment and receipt. Between 10:00 and 11:00 checkout is free. The charge moves `paid_until` forward (invariant: `paid_until` = latest charge `period_end`). |
| BR-8 | **Early checkout refund:** nights not yet started are refunded at the stay's price. The night in progress is never refunded. The amount is calculated by the system and cannot be typed or changed by anyone. |
| BR-8a | **Refunds need the owner's approval.** At early checkout the stay closes at once (bed → Available, not_cleaned) and a refund **request** is created for the calculated amount. Only users with `approveRefund` (the owner) can approve or reject it; a rejection needs a reason. The approver cannot change the amount, and nobody can approve a refund they requested themselves (rejecting it is allowed). |
| BR-8b | **Paying an approved refund:** a user with `payRefund` records the payout from the **cash drawer** or the **Paybill account** (method `cash` or `paybill`; `paybill` requires the M-Pesa transaction code of the money sent). The payout needs an open shift, gets a receipt number from the same counter, and is counted in that shift: cash payouts reduce expected cash, Paybill payouts reduce the Paybill total. Requested and approved-but-unpaid refunds appear in the alerts. |
| BR-9 | Checkout → bed `not_cleaned`. Only completing a housekeeping task sets `clean`. A reactivated bed or room starts `not_cleaned`; a new bed starts `clean`. |
| BR-10 | An M-Pesa code can be used once across all payments and refund payouts. Required for `paybill`, null for `cash`. Methods are `cash` and `paybill` everywhere; screens label `paybill` as "M-Pesa". |
| BR-11 | Stays, payments, charges, refunds, refund decisions and audit entries are never edited or deleted by users. Corrections are `voids` rows with a reason, by users with `voidRecords` permission. Voided payments and refund payouts are excluded from totals. |
| BR-12 | Every payment and refund payout belongs to an open shift. No open shift → no check-in, extension, late-checkout charge, payment or refund payout. (Requesting a refund at checkout also requires the open shift, because checkout does.) |
| BR-13 | **Permissions are checked by action**, through one permission map (`Permission` enum → allowed roles). Never compare roles in features. Roles: `owner` (signs in on the desk to Today, Prices and Staff, and later on the phone: sets prices and categories, approves refunds, decides price changes, manages supervisors, sees all reports and the audit trail; works without a shift; first run creates the owner), `supervisor` (runs the desk: setup, staff, settings, voids, shift oversight, backups, all front-desk work; was `admin` before schema v6) and `receptionist` (front-desk work). A new role is added by editing only the map. |

## Refund lifecycle

```
early checkout ──► requested ──(owner approves)──► approved ──(payout recorded)──► paid
                       └──────(owner rejects + reason)──► rejected
```

- Status is derived, never stored as free text: no decision row → `requested`; decision `rejected` → `rejected`; decision `approved` and no payout → `approved`; payout recorded → `paid`.
- The owner decides from the business view (phone, sprint 2, needs sync); the payout is recorded at the desk by a supervisor or receptionist with an open shift.
- Totals count a refund only when it is **paid**, in the shift that paid it.

## Calculations

```dart
// Inputs in Africa/Nairobi local time; convert results back to UTC for storage.

DateTime firstCheckout(DateTime checkInLocal, ClockTime checkout) {
  final arrivalDate = DateTime(checkInLocal.year, checkInLocal.month, checkInLocal.day);
  return _at(_addDays(arrivalDate, 1), checkout);
}

DateTime paidUntil(DateTime firstCheckout, int nights) => _addDays(firstCheckout, nights - 1);

int totalDue(int nights, int pricePerNight) => nights * pricePerNight;

// Extension: period_start = paidUntil, period_end = _addDays(paidUntil, n).

enum Occupancy { available, occupied, overstay }

Occupancy occupancyOf({Stay? activeStay, required DateTime now, required int graceMinutes}) {
  if (activeStay == null) return Occupancy.available;
  final overstayAt = activeStay.paidUntil.add(Duration(minutes: graceMinutes));
  return now.isAfter(overstayAt) ? Occupancy.overstay : Occupancy.occupied;
}

/// Nights to charge before a checkout at [now]: 0 if within grace, else every night started.
int lateNights(DateTime paidUntil, DateTime now, int graceMinutes) {
  final after = now.difference(paidUntil.add(Duration(minutes: graceMinutes)));
  if (after <= Duration.zero) return 0;
  return after.inDays + 1;
}

/// Nights used when leaving at [now] for a stay with [nightsPaid] nights.
/// Night 1 is always used; night k (k ≥ 2) counts once now is past its start + grace.
int nightsUsed(DateTime firstCheckout, DateTime now, int graceMinutes, int nightsPaid) {
  final elapsed = now.difference(firstCheckout.add(Duration(minutes: graceMinutes)));
  final used = elapsed <= Duration.zero ? 1 : 2 + elapsed.inDays;
  return used > nightsPaid ? nightsPaid : used;
}

int refundNights(int nightsPaid, int used) => nightsPaid - used;      // 0 → no refund request
int refundAmount(int refundNights, int pricePerNight) => refundNights * pricePerNight;

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
| Extension | Occupied (paid_until moves forward) | unchanged |
| Checkout (incl. late charge or refund request) | Available | not_cleaned |
| Housekeeping task completed | unchanged | clean |
| Stay voided by a supervisor | Available | not_cleaned |

## Required test cases

Every one of these must exist as a unit test in the matching `domain/` test file (times are Nairobi local):

1. Check-in Thu 19:00, 1 night → checkout Fri 10:00; total = price.
2. Check-in Thu 13:00 → Fri 10:00. Thu 07:00 → Fri 10:00. Thu 09:59 → Fri 10:00.
3. Check-in Thu 03:00 → **Fri** 10:00. Thu 00:30 → Fri 10:00. Wed 23:59 → Thu 10:00.
4. Check-in Thu 15 Oct 19:00, 10 nights → paid_until Sun 25 Oct 10:00; total = 10 × price.
5. paid_until 10:00: now 10:59 → Occupied; now 11:00 → Occupied; now 11:00:01 → Overstay.
6. Extension of 1 night entered at 11:40 with paid_until Fri 10:00 → new paid_until Sat 10:00.
7. Category price changes 700 → 750 after check-in → extension, late charge and refund all use 700.
8. Checkout at 10:45 (within grace) → no late charge. Checkout at 11:30 → 1 night charged and paid_until moves forward. Checkout two days late at 12:00 → 3 nights charged.
9. 10 nights from Thu 15 Oct 19:00, checkout Wed 21 Oct 15:00 → nights used 7, refund request 3 × price.
10. 10 nights from Thu 15 Oct 19:00, checkout Fri 16 Oct 10:30 → used 1, refund 9. Checkout Fri 16 Oct 11:30 → used 2, refund 8.
11. 1-night stay, early checkout → refund 0, no refund request created.
12. Refund lifecycle: new request → `requested`; receptionist or supervisor cannot approve; owner approves → `approved`; the requester cannot approve their own request; owner rejects without reason → refused; payout before approval → refused; payout after approval → `paid`; second payout → refused; approver cannot change the amount.
13. Cash payout reduces the paying shift's expected cash; Paybill payout reduces its Paybill total; requested/approved-unpaid refunds change no totals; voided payout is excluded.
14. Both beds of a 2-bed room for one guest → two stays, one payment, amount = sum of both charges.
15. Bed not_cleaned → cannot let. Bed inactive → cannot let. Bed with active stay → cannot let.
16. Paybill without code → rejected. Reused code (in payments or refund payouts) → rejected. Cash with code → rejected.
17. Payment or refund payout without an open shift → rejected.
18. Permission map: receptionist cannot edit prices, void, manage users or approve refunds; the supervisor voids and manages users; only the owner edits prices and approves refunds; the owner has no front-desk permissions. Every `Permission` is assigned to at least one role. Features call the map, never compare roles.

## Receipts

- Number format `R-000041` (prefix from settings, 6 digits, gap-free per device via `receipt_counter`, incremented in the payment or refund-payout transaction).
- Payment receipt: lodging name header; receipt number, guest, room and bed, category, nights × price, check-in, **check out by** (date, 10:00), amount, method, M-Pesa code, receptionist, date/time.
- Refund receipt (printed at payout): same layout, titled `REFUND`, shows nights refunded × price as a negative amount, the original receipt numbers, who approved it and who paid it.
- Reprints after the first are marked "Copy" (`print_count`).

## Guests

- Required: full name, phone. Optional: ID type (`national_id`, `passport`, `alien_id`) and ID number.
- If an ID number is entered, ID type is required and the pair must be unique.
- Search by phone or ID number, as the user types.
