/// Checkout (FD-8): which of the three it is at a given moment, what the
/// panel says about it, and what a confirmation may still record. Pure
/// Dart, built on the stay rules (BR-7a, BR-8, BR-9).
library;

import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../payments/domain/payment_rules.dart';
import 'stay_rules.dart';

String _nights(int n) => '$n ${n == 1 ? 'night' : 'nights'}';

/// What checking out at a moment means for a stay.
sealed class CheckoutTerms {
  const CheckoutTerms();

  /// The panel's button.
  String get button;
}

/// Prepaid nights haven't started: the stay closes now and a refund of them
/// is requested for the owner's approval (BR-8, BR-8a).
final class EarlyCheckout extends CheckoutTerms {
  const EarlyCheckout({
    required this.nightsPaid,
    required this.nightsUsed,
    required this.refund,
  });

  final int nightsPaid;

  /// The night in progress counts as used.
  final int nightsUsed;
  final RefundTerms refund;

  @override
  String get button =>
      'Check out and request refund of ${formatKes(refund.amount)}';
}

/// Within the paid time and grace: free.
final class OnTimeCheckout extends CheckoutTerms {
  const OnTimeCheckout();

  @override
  String get button => 'Check out';
}

/// After paid_until + grace: every night started is charged first, with
/// its own payment and receipt (BR-7a).
final class LateCheckout extends CheckoutTerms {
  const LateCheckout(this.charge, {required this.chargedSince});

  /// A `late_checkout` charge at the stay's price.
  final ChargeLine charge;

  /// UTC: when the latest of its nights became chargeable (its start plus
  /// grace), e.g. Fri 11:00.
  final DateTime chargedSince;

  @override
  String get button => 'Charge ${_nights(charge.nights)} and check out';
}

/// Checking [stay] out at [now].
CheckoutTerms checkoutTerms(Stay stay, DateTime now, int graceMinutes) {
  final late = lateCheckoutCharge(stay, now, graceMinutes);
  if (late != null) {
    return LateCheckout(
      late,
      chargedSince: addNairobiDays(
        late.periodStart,
        late.nights - 1,
      ).add(Duration(minutes: graceMinutes)),
    );
  }
  final refund = earlyCheckoutRefund(stay, now, graceMinutes);
  if (refund == null) return const OnTimeCheckout();
  return EarlyCheckout(
    nightsPaid: stay.nightsPaid,
    nightsUsed: stay.nightsPaid - refund.nights,
    refund: refund,
  );
}

/// Whole minutes [now] is past paid_until + grace; 0 within it.
int minutesPastGrace(DateTime paidUntil, DateTime now, int graceMinutes) {
  final past = now.difference(paidUntil.add(Duration(minutes: graceMinutes)));
  return past.isNegative ? 0 : past.inMinutes;
}

/// Null if confirming now does what the panel showed ([shown]); otherwise
/// what changed and what to do. A night starting, or the grace ending,
/// while the panel was open changes the money, so it is never applied
/// silently.
String? checkoutChange(CheckoutTerms shown, CheckoutTerms now) {
  switch ((shown, now)) {
    case (OnTimeCheckout(), OnTimeCheckout()):
      return null;
    case (EarlyCheckout(refund: final a), EarlyCheckout(refund: final b))
        when a.nights == b.nights:
      return null;
    case (LateCheckout(charge: final a), LateCheckout(charge: final b))
        when a.nights == b.nights:
      return null;
    case (_, LateCheckout(:final charge, :final chargedSince)):
      return 'It’s now past ${formatTime(chargedSince)}, so ${_nights(charge.nights)} '
          '${charge.nights == 1 ? 'is' : 'are'} charged. Check and confirm '
          'again.';
    case (_, EarlyCheckout(:final refund)):
      return 'Another night has started, so ${_nights(refund.nights)} '
          '(${formatKes(refund.amount)}) is refunded now. Check and confirm '
          'again.';
    case (_, OnTimeCheckout()):
      return 'Another night has started, so there is nothing to refund now. '
          'Check and confirm again.';
  }
}

/// Null if the late charge can be paid this way: Cash, or M-Pesa with a
/// code not used before (BR-10).
String? latePaymentError(
  PaymentMethod? method,
  String? code, {
  required MpesaCodeUse? codeUsedOn,
}) {
  if (method == null) return 'Choose how they paid.';
  return mpesaCodeError(
    method,
    code,
    codeInUse: codeUsedOn != null,
    usedOn: codeUsedOn,
  );
}

/// The confirmation before a free or refund checkout. A late checkout has
/// none: its payment form is the confirmation.
String checkoutConfirmText({
  required String guestName,
  required String roomNumber,
  required String bedLabel,
  required CheckoutTerms terms,
}) =>
    'Check out $guestName from Room $roomNumber, Bed $bedLabel? '
    '${switch (terms) {
      EarlyCheckout(:final refund) => 'A refund of ${formatKes(refund.amount)} '
          'will be requested for the owner’s approval. ',
      _ => '',
    }}'
    'The bed will need cleaning.';
