/// Extending a stay (FD-7, BR-7): n more nights from `paid_until`, at the
/// stay's locked price, with its own payment and receipt. Pure Dart, built
/// on the stay rules.
library;

import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import 'check_in.dart';
import 'stay_rules.dart';

String _nights(int n) => '$n ${n == 1 ? 'night' : 'nights'}';

/// The fewest nights an extension may add at [now]: the nights already
/// started past grace, counted by [lateNights] exactly as a late checkout
/// would charge them, so the bed isn't still Overstay right after paying.
/// Within grace (or before), 1.
int extendMinNights(Stay stay, DateTime now, int graceMinutes) {
  final started = lateNights(stay.paidUntil, now, graceMinutes);
  return started < 1 ? 1 : started;
}

/// Why the minimum is above 1, for under the stepper; null when it's 1.
String? minNightsReason(Stay stay, DateTime now, int graceMinutes) {
  final min = extendMinNights(stay, now, graceMinutes);
  if (min <= 1) return null;
  return 'At least $min nights: $min have started since '
      '${formatWeekdayTime(stay.paidUntil)}.';
}

/// The most nights the stepper offers: 30, or the minimum if that's more.
int extendMaxNights(int minNights) =>
    minNights > nightsRange.max ? minNights : nightsRange.max;

/// Null if [nights] can be added when at least [minNights] are needed.
String? extendNightsError(int? nights, {required int minNights}) {
  if (nights == null) return 'Enter the number of nights.';
  if (nights < nightsRange.min || nights > extendMaxNights(minNights)) {
    return 'Choose ${nightsRange.min} to ${extendMaxNights(minNights)} '
        'nights.';
  }
  if (nights < minNights) {
    return 'At least $minNights nights: that many have already started.';
  }
  return null;
}

/// What the Extend card shows and the save records.
final class ExtendQuote {
  const ExtendQuote(this.charge);

  /// An `extension` charge from paid_until (BR-7).
  final ChargeLine charge;

  int get nights => charge.nights;

  /// UTC: the new check-out-by time.
  DateTime get newPaidUntil => charge.periodEnd;

  /// Whole KES.
  int get total => charge.amount;

  String get newCheckoutText => formatDayDateComma(newPaidUntil);

  /// `2 × KES 700 (check-in price)`.
  String get priceLine =>
      '${charge.nights} × ${formatKes(charge.pricePerNight)} (check-in price)';

  String get button => 'Extend and issue receipt';
}

ExtendQuote quoteExtend(Stay stay, int nights) =>
    ExtendQuote(extensionCharge(stay, nights));

/// Null if saving now records what the panel showed: the stay's paid_until
/// is unchanged and [nights] still covers the nights started by now.
String? extendChange({
  required DateTime shownPaidUntil,
  required DateTime nowPaidUntil,
  required int nights,
  required int nowMinNights,
}) {
  if (nowPaidUntil != shownPaidUntil) {
    return 'This stay was extended meanwhile: it’s now paid to '
        '${formatDayDateComma(nowPaidUntil)}. Check and extend again.';
  }
  if (nights < nowMinNights) {
    return 'Another night has started, so at least ${_nights(nowMinNights)} '
        'are needed now. Check and extend again.';
  }
  return null;
}
