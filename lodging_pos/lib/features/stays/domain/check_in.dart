/// Check-in (FD-4) with its payment (FD-5): what the screen shows, what a
/// save may record, and why a bed can't be let. Pure Dart.
library;

import '../../../core/clock/clock_time.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../guests/domain/guest.dart';
import '../../payments/domain/payment_rules.dart';
import '../../setup/domain/rooms.dart';
import 'stay_rules.dart';

/// A check-in is for 1 to 30 nights (owner's decision).
const nightsRange = (min: 1, max: 30);

/// Null if [nights] can be let.
String? nightsError(int? nights) {
  if (nights == null) return 'Enter the number of nights.';
  if (nights < nightsRange.min || nights > nightsRange.max) {
    return 'Choose ${nightsRange.min} to ${nightsRange.max} nights.';
  }
  return null;
}

/// Nights as typed into the stepper: whole digits only, else null.
int? parseNights(String text) {
  final t = text.trim();
  return RegExp(r'^\d{1,3}$').hasMatch(t) ? int.parse(t) : null;
}

/// Why [bed] can't be let now (BR-5), or null if it can: closed, has a
/// guest, or needs cleaning, in that order. Agrees with [canLet].
String? letBlocker(BedSummary bed, Occupancy occupancy) {
  final name = 'Bed ${bed.label.code}';
  if (!bed.isActive) return '$name is closed';
  if (occupancy != Occupancy.available) return '$name has a guest';
  if (bed.cleanliness != Cleanliness.clean) return '$name needs cleaning first';
  return null;
}

/// What the check-in screen shows before saving: each bed at its category's
/// price, the dates and the total. A save works it out again and refuses if
/// anything differs ([quoteChange]), so nobody is charged or promised
/// something they didn't see.
final class CheckInQuote {
  const CheckInQuote._(this.beds, this.nights, this.plan, this.checkout);

  final List<LetBed> beds;
  final int nights;
  final CheckInPlan plan;

  /// The checkout time setting it was worked out with.
  final ClockTime checkout;

  /// UTC.
  DateTime get checkInAt => plan.stays.first.charge.periodStart;

  /// UTC: the check-out-by time, 10:00 (BR-6).
  DateTime get paidUntil => plan.stays.first.charge.periodEnd;

  /// Whole KES: what the one payment must be (FD-5).
  int get total => plan.paymentAmount;
}

/// [beds] (one or both of a room) for [nights] from [checkInAt].
CheckInQuote quoteCheckIn({
  required DateTime checkInAt,
  required int nights,
  required ClockTime checkout,
  required List<LetBed> beds,
}) => CheckInQuote._(
  List.unmodifiable(beds),
  nights,
  planCheckIn(
    checkInAt: checkInAt,
    nights: nights,
    checkout: checkout,
    beds: beds,
  ),
  checkout,
);

/// Null if a save at [now] records what [shown] promised; otherwise what
/// changed and what to do. The caller works out [now] with the same beds
/// and nights, at the save's time and current prices and settings.
String? quoteChange(CheckInQuote shown, CheckInQuote now) {
  final current = {for (final b in now.beds) b.bedId: b};
  for (final was in shown.beds) {
    final b = current[was.bedId];
    if (b == null) return 'The beds changed. Check and save again.';
    if (b.categoryId != was.categoryId) {
      return 'This bed is now ${b.categoryName} at '
          '${formatKes(b.pricePerNight)} a night. Check the total and save '
          'again.';
    }
    if (b.pricePerNight != was.pricePerNight) {
      return '${b.categoryName} is now ${formatKes(b.pricePerNight)} a night. '
          'Check the total and save again.';
    }
  }
  if (now.paidUntil != shown.paidUntil) {
    final ends = formatDayDateComma(now.paidUntil);
    if (_day(now.checkInAt) != _day(shown.checkInAt)) {
      return 'It’s now past midnight, so checkout is $ends. Check and save '
          'again.';
    }
    return 'Checkout is now ${now.checkout.format()}, so this stay ends '
        '$ends. Check and save again.';
  }
  return null;
}

DateTime _day(DateTime utc) {
  final t = toNairobi(utc);
  return DateTime.utc(t.year, t.month, t.day);
}

/// Who the check-in is for.
sealed class GuestChoice {
  const GuestChoice();
}

/// A guest already registered.
final class ReturningGuest extends GuestChoice {
  const ReturningGuest(this.guestId);
  final String guestId;
}

/// A guest registered by this check-in, in the same transaction, so a
/// cancelled or failed check-in leaves no stray guest.
final class NewGuest extends GuestChoice {
  const NewGuest(this.form, {this.phoneSharedWith = const {}});
  final GuestForm form;

  /// Guests the form showed as already having this phone (allowed: families
  /// share phones). Anyone else with it by the time of saving is news, so the
  /// save stops to show them.
  final Set<String> phoneSharedWith;
}

/// A check-in and its payment, as the receptionist confirmed them.
final class CheckInRequest {
  const CheckInRequest({
    required this.guest,
    required this.method,
    required this.mpesaCode,
    required this.shown,
  });

  final GuestChoice guest;
  final PaymentMethod method;
  final String? mpesaCode;

  /// What the screen showed: beds, nights, dates and total.
  final CheckInQuote shown;
}

enum CheckInField { beds, guest, nights, mpesaCode }

/// Errors per field; empty if [r] can be saved. [codeUsedOn] is where the
/// M-Pesa code was already used, looked up by the caller (BR-10).
Map<CheckInField, String> validateCheckIn(
  CheckInRequest r, {
  required MpesaCodeUse? codeUsedOn,
}) {
  final bedIds = {for (final b in r.shown.beds) b.bedId};
  final guest = r.guest;
  return {
    if (bedIds.isEmpty ||
        bedIds.length != r.shown.beds.length ||
        bedIds.length > 2)
      CheckInField.beds: 'Choose a bed.',
    if (guest is NewGuest && validateGuest(guest.form).isNotEmpty)
      CheckInField.guest: 'Check the new guest’s details.',
    CheckInField.nights: ?nightsError(r.shown.nights),
    CheckInField.mpesaCode: ?mpesaCodeError(
      r.method,
      r.mpesaCode,
      codeInUse: codeUsedOn != null,
      usedOn: codeUsedOn,
    ),
  };
}

/// `Room 7, Bed A` or `Room 7, Beds A and B`.
String checkedInSummary({
  required String roomNumber,
  required List<BedLabel> labels,
}) => labels.length == 1
    ? 'Room $roomNumber, Bed ${labels.single.code}'
    : 'Room $roomNumber, Beds ${labels.map((l) => l.code).join(' and ')}';
