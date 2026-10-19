import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/stays/domain/check_out.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

DateTime oct(int day, int hour, [int minute = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute);

const grace = 60;

/// Room 5 Bed B, Deluxe 700, checked in at [at] for [nights].
Stay stay(DateTime at, int nights) => Stay.fromCheckIn(
  id: 'stay-1',
  bedId: 'bed-5b',
  charge: planCheckIn(
    checkInAt: at,
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
  group('which checkout (required test cases 8–11)', () {
    test('early: nights not started are refunded at the stay’s price', () {
      // 10 nights from Thu 15 19:00, leaving Wed 21 15:00: 7 used, 3 back.
      final terms = checkoutTerms(stay(oct(15, 19), 10), oct(21, 15), grace);
      expect(terms, isA<EarlyCheckout>());
      final early = terms as EarlyCheckout;
      expect((early.nightsPaid, early.nightsUsed), (10, 7));
      expect((early.refund.nights, early.refund.amount), (3, 2100));
      expect(early.button, 'Check out and request refund of KES 2,100');
    });

    test('on time: a 1-night stay, or within the paid time and grace', () {
      expect(
        checkoutTerms(stay(oct(15, 19), 1), oct(16, 8), grace),
        isA<OnTimeCheckout>(),
      );
      // Paid to Fri 10:00: 10:45 is within grace.
      final t = checkoutTerms(stay(oct(15, 19), 1), oct(16, 10, 45), grace);
      expect(t, isA<OnTimeCheckout>());
      expect(t.button, 'Check out');
    });

    test('late: each night started after grace, at the stay’s price', () {
      final one = checkoutTerms(stay(oct(15, 19), 1), oct(16, 11, 30), grace);
      expect(one, isA<LateCheckout>());
      final late = one as LateCheckout;
      expect((late.charge.nights, late.charge.amount), (1, 700));
      expect(late.charge.kind, ChargeKind.lateCheckout);
      expect(late.charge.categoryName, 'Deluxe');
      expect(late.button, 'Charge 1 night and check out');

      // Two days late at 12:00: 3 nights.
      final three = checkoutTerms(stay(oct(15, 19), 1), oct(18, 12), grace);
      expect((three as LateCheckout).charge.nights, 3);
      expect(three.button, 'Charge 3 nights and check out');
    });
  });

  test('minutes past grace, for the overstay banner', () {
    final s = stay(oct(15, 19), 1); // paid to Fri 10:00, grace to 11:00
    expect(minutesPastGrace(s.paidUntil, oct(16, 11, 24), grace), 24);
    expect(minutesPastGrace(s.paidUntil, oct(16, 10, 30), grace), 0);
  });

  group('checkoutChange: confirming never does what the panel didn’t say', () {
    CheckoutTerms at(DateTime now, {int nights = 1}) =>
        checkoutTerms(stay(oct(15, 19), nights), now, grace);

    test('the same terms a little later: fine', () {
      expect(checkoutChange(at(oct(16, 9)), at(oct(16, 10, 50))), isNull);
      expect(checkoutChange(at(oct(16, 11, 30)), at(oct(16, 12, 30))), isNull);
    });

    test('opened within grace, confirmed after: one night is charged', () {
      expect(
        checkoutChange(at(oct(16, 10, 58)), at(oct(16, 11, 1))),
        'It’s now past 11:00, so 1 night is charged. Check and confirm '
        'again.',
      );
    });

    test('another night started while the panel was open', () {
      expect(
        checkoutChange(at(oct(17, 9)), at(oct(17, 11, 5))),
        'It’s now past 11:00, so 2 nights are charged. Check and confirm '
        'again.',
      );
    });

    test('a refund night started while the panel was open', () {
      // 3 nights from Thu: Fri 10:30 → 1 used, 2 back; Fri 11:05 → 2 used.
      expect(
        checkoutChange(
          at(oct(16, 10, 30), nights: 3),
          at(oct(16, 11, 5), nights: 3),
        ),
        'Another night has started, so 1 night (KES 700) is refunded now. '
        'Check and confirm again.',
      );
      // … and the last one: nothing left to refund.
      expect(
        checkoutChange(
          at(oct(17, 10, 30), nights: 3),
          at(oct(17, 11, 5), nights: 3),
        ),
        'Another night has started, so there is nothing to refund now. '
        'Check and confirm again.',
      );
    });
  });

  group('the late charge’s payment', () {
    test('Cash, or M-Pesa with an unused code (BR-10)', () {
      expect(
        latePaymentError(null, null, codeUsedOn: null),
        'Choose how '
        'they paid.',
      );
      expect(
        latePaymentError(PaymentMethod.cash, null, codeUsedOn: null),
        isNull,
      );
      expect(
        latePaymentError(PaymentMethod.paybill, '', codeUsedOn: null),
        'Enter the M-Pesa code.',
      );
      expect(
        latePaymentError(
          PaymentMethod.paybill,
          'qjk7h2lm4p',
          codeUsedOn: MpesaCodeUse(
            receiptNumber: 'R-000038',
            at: oct(15, 11, 2),
          ),
        ),
        'QJK7H2LM4P was already used on receipt R-000038 (Thu 15 Oct, '
        '11:02).',
      );
    });
  });

  test('the confirmation says what will happen', () {
    final early = checkoutTerms(stay(oct(15, 19), 10), oct(21, 15), grace);
    expect(
      checkoutConfirmText(
        guestName: 'Peter Kamau',
        roomNumber: '5',
        bedLabel: 'B',
        terms: early,
      ),
      'Check out Peter Kamau from Room 5, Bed B? A refund of KES 2,100 will '
      'be requested for the owner’s approval. The bed will need cleaning.',
    );
    expect(
      checkoutConfirmText(
        guestName: 'Peter Kamau',
        roomNumber: '5',
        bedLabel: 'B',
        terms: const OnTimeCheckout(),
      ),
      'Check out Peter Kamau from Room 5, Bed B? The bed will need cleaning.',
    );
  });
}
