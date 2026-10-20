import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/stays/domain/check_out.dart';
import 'package:lodging_pos/features/stays/domain/extend.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

DateTime oct(int day, int hour, [int minute = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute);

const grace = 60;

/// Deluxe 700, checked in Thu 15 Oct 19:00 for [nights]: 1 night → paid to
/// Fri 16 Oct, 10:00.
Stay stay({int nights = 1}) => Stay.fromCheckIn(
  id: 'stay-1',
  bedId: 'bed-5b',
  charge: planCheckIn(
    checkInAt: oct(15, 19),
    nights: nights,
    checkout: const ClockTime(10, 0),
    beds: const [
      LetBed(
        bedId: 'bed-5b',
        categoryId: 'deluxe',
        categoryName: 'Deluxe',
        pricePerNight: 700,
      ),
    ],
  ).stays.single.charge,
);

void main() {
  group('the minimum when late (decision 1)', () {
    test('equals the late-checkout night count at the same moment, so '
        'extending and checking out count the same started nights', () {
      final s = stay(); // paid to Fri 10:00
      for (final (now, expected) in [
        (oct(16, 10, 30), 1), // within grace: minimum 1
        (oct(16, 11, 1), 1), // Fri night started
        (oct(17, 12), 2), // Sat 12:00
        (oct(18, 12), 3), // Sun 12:00
      ]) {
        final late = checkoutTerms(s, now, grace);
        final lateCount = late is LateCheckout ? late.charge.nights : 0;
        expect(
          extendMinNights(s, now, grace),
          lateCount < 1 ? 1 : lateCount,
          reason: '$now',
        );
        expect(extendMinNights(s, now, grace), expected, reason: '$now');
      }
    });

    test('says why when more than 1 night is needed', () {
      final s = stay();
      expect(minNightsReason(s, oct(16, 11, 1), grace), isNull);
      expect(
        minNightsReason(s, oct(18, 12), grace),
        'At least 3 nights: 3 have started since Fri 10:00.',
      );
    });
  });

  group('nights', () {
    test('1–30, and at least the minimum', () {
      expect(extendNightsError(1, minNights: 1), isNull);
      expect(extendNightsError(30, minNights: 1), isNull);
      expect(
        extendNightsError(null, minNights: 1),
        'Enter the number of nights.',
      );
      expect(extendNightsError(0, minNights: 1), 'Choose 1 to 30 nights.');
      expect(extendNightsError(31, minNights: 1), 'Choose 1 to 30 nights.');
      expect(
        extendNightsError(2, minNights: 3),
        'At least 3 nights: that many have already started.',
      );
      expect(extendNightsError(3, minNights: 3), isNull);
    });
  });

  group('the quote (BR-7)', () {
    test('n nights from paid_until at the check-in price, whenever it is '
        'entered', () {
      final q = quoteExtend(stay(), 2);
      expect(q.charge.kind, ChargeKind.extension);
      expect(q.charge.periodStart, oct(16, 10));
      expect(q.newPaidUntil, oct(18, 10));
      expect((q.charge.pricePerNight, q.total), (700, 1400));
      expect(q.charge.categoryName, 'Deluxe');
      expect(q.button, 'Extend and issue receipt');
      expect(q.priceLine, '2 × KES 700 (check-in price)');
      expect(q.newCheckoutText, 'Sun 18 Oct, 10:00');
    });

    test('an overstay extended by the minimum is no longer an overstay', () {
      final s = stay();
      final now = oct(18, 12); // Sun 12:00, 3 nights started
      final q = quoteExtend(s, extendMinNights(s, now, grace));
      expect(q.newPaidUntil, oct(19, 10)); // Mon 10:00
      expect(
        occupancyAt(paidUntil: q.newPaidUntil, now: now, graceMinutes: grace),
        Occupancy.occupied,
      );
    });
  });

  group('extendChange: saving never does what the panel didn’t show', () {
    test('nothing moved: fine', () {
      final s = stay();
      expect(
        extendChange(
          shownPaidUntil: s.paidUntil,
          nowPaidUntil: s.paidUntil,
          nights: 1,
          nowMinNights: 1,
        ),
        isNull,
      );
    });

    test('someone else extended it meanwhile', () {
      expect(
        extendChange(
          shownPaidUntil: oct(16, 10),
          nowPaidUntil: oct(17, 10),
          nights: 1,
          nowMinNights: 1,
        ),
        'This stay was extended meanwhile: it’s now paid to Sat 17 Oct, '
        '10:00. Check and extend again.',
      );
    });

    test('another night started while the panel was open', () {
      expect(
        extendChange(
          shownPaidUntil: oct(16, 10),
          nowPaidUntil: oct(16, 10),
          nights: 1,
          nowMinNights: 2,
        ),
        'Another night has started, so at least 2 nights are needed now. '
        'Check and extend again.',
      );
    });
  });

  test('a later early checkout refunds across both charges at the locked '
      'price', () {
    // 2 nights from Thu (paid to Sat 10:00), extended by 3: paid to Tue
    // 10:00, 5 nights.
    final s = stay(nights: 2);
    final extended = s.withCharge(quoteExtend(s, 3).charge);
    expect(extended.nightsPaid, 5);
    // Leaving Sat 15:00: Thu, Fri and Sat nights used; Sun and Mon back.
    final terms = checkoutTerms(extended, oct(17, 15), grace);
    final early = terms as EarlyCheckout;
    expect((early.nightsUsed, early.refund.nights), (3, 2));
    expect(early.refund.amount, 1400);
  });
}
