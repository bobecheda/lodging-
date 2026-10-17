/// Per-night stay rules (lodging-rules skill, BR-1 to BR-8). Pure Dart.
///
/// Every `DateTime` in and out is a UTC instant, as stored. Wall-clock rules
/// (10:00 checkout, calendar days) are applied in Africa/Nairobi time through
/// `core/clock/nairobi.dart`.
library;

import '../../../core/clock/clock_time.dart';
import '../../../core/clock/nairobi.dart';
import '../../setup/domain/rooms.dart';

/// As stored in `stay_charges.kind`.
enum ChargeKind {
  checkIn('check_in'),
  extension('extension'),
  lateCheckout('late_checkout');

  const ChargeKind(this.code);
  final String code;

  static ChargeKind parse(String code) =>
      values.firstWhere((k) => k.code == code);
}

/// One `stay_charges` row: [nights] at the stay's [pricePerNight], covering
/// [periodStart] → [periodEnd].
final class ChargeLine {
  const ChargeLine({
    required this.kind,
    required this.nights,
    required this.pricePerNight,
    required this.periodStart,
    required this.periodEnd,
  });

  final ChargeKind kind;
  final int nights;

  /// Whole KES, locked at check-in (BR-3).
  final int pricePerNight;
  final DateTime periodStart;
  final DateTime periodEnd;

  int get amount => totalDue(nights, pricePerNight);
}

/// A stay as the rules see it: its charges, in order, the first being the
/// check-in.
final class Stay {
  Stay._(this.id, this.bedId, this.charges);

  /// A stay from its check-in charge.
  factory Stay.fromCheckIn({
    required String id,
    required String bedId,
    required ChargeLine charge,
  }) {
    if (charge.kind != ChargeKind.checkIn) {
      throw ArgumentError.value(charge.kind, 'charge', 'not a check-in');
    }
    return Stay._(id, bedId, List.unmodifiable([charge]));
  }

  final String id;
  final String bedId;
  final List<ChargeLine> charges;

  DateTime get checkInAt => charges.first.periodStart;

  /// 10:00 after the first night.
  DateTime get firstCheckout =>
      addNairobiDays(charges.first.periodEnd, 1 - charges.first.nights);

  /// The latest charge's end (BR-6, BR-7a).
  DateTime get paidUntil => charges.last.periodEnd;

  int get nightsPaid => charges.fold(0, (n, c) => n + c.nights);

  /// The price every later charge and refund of this stay uses (BR-3).
  int get pricePerNight => charges.first.pricePerNight;

  /// This stay after [charge] (an extension or late-checkout charge).
  Stay withCharge(ChargeLine charge) =>
      Stay._(id, bedId, List.unmodifiable([...charges, charge]));
}

void _requireNights(int nights) {
  if (nights < 1) {
    throw ArgumentError.value(nights, 'nights', 'must be at least 1');
  }
}

/// BR-1a: 10:00 (or [checkout]) on the Nairobi calendar day after arrival,
/// whatever the arrival time.
DateTime firstCheckout(DateTime checkInAt, ClockTime checkout) {
  final arrival = toNairobi(checkInAt);
  return nairobiInstant(
    arrival.year,
    arrival.month,
    arrival.day + 1,
    checkout.hour,
    checkout.minute,
  );
}

/// BR-6: first checkout + (nights − 1) days.
DateTime paidUntil(DateTime firstCheckout, int nights) {
  _requireNights(nights);
  return addNairobiDays(firstCheckout, nights - 1);
}

/// Whole KES.
int totalDue(int nights, int pricePerNight) => nights * pricePerNight;

/// One bed of a check-in and its charge.
typedef PlannedStay = ({String bedId, ChargeLine charge});

/// A check-in: one stay per bed, all paid by one payment (BR-4).
final class CheckInPlan {
  const CheckInPlan(this.stays);
  final List<PlannedStay> stays;

  /// The single payment covers every bed's charge.
  int get paymentAmount => stays.fold(0, (sum, s) => sum + s.charge.amount);
}

/// Plans letting [beds] (each at its category's current price) for [nights]
/// from [checkInAt].
CheckInPlan planCheckIn({
  required DateTime checkInAt,
  required int nights,
  required ClockTime checkout,
  required List<({String bedId, int pricePerNight})> beds,
}) {
  _requireNights(nights);
  final end = paidUntil(firstCheckout(checkInAt, checkout), nights);
  return CheckInPlan([
    for (final bed in beds)
      (
        bedId: bed.bedId,
        charge: ChargeLine(
          kind: ChargeKind.checkIn,
          nights: nights,
          pricePerNight: bed.pricePerNight,
          periodStart: checkInAt,
          periodEnd: end,
        ),
      ),
  ]);
}

/// BR-7: [nights] more from `paid_until`, whenever it is entered.
ChargeLine extensionCharge(Stay stay, int nights) {
  _requireNights(nights);
  return ChargeLine(
    kind: ChargeKind.extension,
    nights: nights,
    pricePerNight: stay.pricePerNight,
    periodStart: stay.paidUntil,
    periodEnd: addNairobiDays(stay.paidUntil, nights),
  );
}

enum Occupancy { available, occupied, overstay }

/// Derived, never stored. Overstay once now is past paid_until + grace.
Occupancy occupancyOf({
  required Stay? activeStay,
  required DateTime now,
  required int graceMinutes,
}) => occupancyAt(
  paidUntil: activeStay?.paidUntil,
  now: now,
  graceMinutes: graceMinutes,
);

/// [occupancyOf] from just the active stay's `paid_until` (null: no active
/// stay), for screens that don't load the whole stay (the bed board).
Occupancy occupancyAt({
  required DateTime? paidUntil,
  required DateTime now,
  required int graceMinutes,
}) {
  if (paidUntil == null) return Occupancy.available;
  final overstayAt = paidUntil.add(Duration(minutes: graceMinutes));
  return now.isAfter(overstayAt) ? Occupancy.overstay : Occupancy.occupied;
}

/// Nights started after [paidUntil] by [now]: night k counts once now is past
/// its start + grace. 0 within grace.
int lateNights(DateTime paidUntil, DateTime now, int graceMinutes) {
  final grace = Duration(minutes: graceMinutes);
  var nights = 0;
  while (now.isAfter(addNairobiDays(paidUntil, nights).add(grace))) {
    nights++;
  }
  return nights;
}

/// BR-7a: the charge for leaving after paid_until + grace, or null when
/// checkout is free. It moves paid_until forward like an extension.
ChargeLine? lateCheckoutCharge(Stay stay, DateTime now, int graceMinutes) {
  final nights = lateNights(stay.paidUntil, now, graceMinutes);
  if (nights == 0) return null;
  return ChargeLine(
    kind: ChargeKind.lateCheckout,
    nights: nights,
    pricePerNight: stay.pricePerNight,
    periodStart: stay.paidUntil,
    periodEnd: addNairobiDays(stay.paidUntil, nights),
  );
}

/// Nights used when leaving at [now]. Night 1 is always used; night k
/// (k ≥ 2) counts once now is past its start + grace. Never more than
/// [nightsPaid].
int nightsUsed(
  DateTime firstCheckout,
  DateTime now,
  int graceMinutes,
  int nightsPaid,
) {
  final grace = Duration(minutes: graceMinutes);
  var used = 1;
  while (used < nightsPaid &&
      now.isAfter(addNairobiDays(firstCheckout, used - 1).add(grace))) {
    used++;
  }
  return used;
}

/// Nights not yet started; 0 means no refund request.
int refundNights(int nightsPaid, int used) => nightsPaid - used;

/// Whole KES, at the stay's locked price.
int refundAmount(int refundNights, int pricePerNight) =>
    refundNights * pricePerNight;

/// What an early checkout refunds (BR-8). The amount is always calculated,
/// never typed.
final class RefundTerms {
  RefundTerms({required this.nights, required this.pricePerNight}) {
    _requireNights(nights);
    if (pricePerNight < 1) {
      throw ArgumentError.value(pricePerNight, 'pricePerNight');
    }
  }

  final int nights;
  final int pricePerNight;

  int get amount => refundAmount(nights, pricePerNight);
}

/// BR-8: the refund for leaving at [now], or null when no night is left.
RefundTerms? earlyCheckoutRefund(Stay stay, DateTime now, int graceMinutes) {
  final used = nightsUsed(
    stay.firstCheckout,
    now,
    graceMinutes,
    stay.nightsPaid,
  );
  final nights = refundNights(stay.nightsPaid, used);
  if (nights == 0) return null;
  return RefundTerms(nights: nights, pricePerNight: stay.pricePerNight);
}

/// BR-5: only an active, available, clean bed can be let.
bool canLet(BedSummary bed, Occupancy occupancy) =>
    bed.isActive &&
    occupancy == Occupancy.available &&
    bed.cleanliness == Cleanliness.clean;
