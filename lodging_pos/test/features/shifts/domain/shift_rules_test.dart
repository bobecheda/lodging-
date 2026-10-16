import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/refunds/domain/refund.dart';
import 'package:lodging_pos/features/shifts/domain/shift.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';

UserAccount user(String id, Role role) => UserAccount(
  id: id,
  fullName: id,
  username: id,
  role: role,
  isActive: true,
  mustChangePassword: false,
);

void main() {
  final jane = user('jane', Role.receptionist);
  final tom = user('tom', Role.receptionist);
  final owner = user('owner', Role.admin);
  final janesShift = OpenShift(
    id: 's1',
    userId: 'jane',
    userName: 'Jane',
    openedAt: DateTime.utc(2026, 10, 14, 5),
    openingFloat: 1000,
  );

  group('openingFloatError', () {
    test('accepts zero and whole positive amounts', () {
      expect(openingFloatError(0), isNull);
      expect(openingFloatError(1000), isNull);
    });

    test('rejects missing and negative amounts', () {
      expect(openingFloatError(null), isNotNull);
      expect(openingFloatError(-1), isNotNull);
    });
  });

  group('shiftStartFor', () {
    test('a receptionist with no open shift must open one', () {
      expect(
        shiftStartFor(openShift: null, user: jane),
        isA<OpenNewShift>(),
      );
    });

    test('a receptionist is asked to resume their own open shift', () {
      final start = shiftStartFor(openShift: janesShift, user: jane);
      expect(start, isA<ResumeShift>());
      expect((start as ResumeShift).shift, janesShift);
    });

    test('once they continue it, they are ready to work', () {
      final start = shiftStartFor(
        openShift: janesShift,
        user: jane,
        resumeConfirmed: true,
      );
      expect(start, isA<ShiftReady>());
      expect((start as ShiftReady).shift, janesShift);
    });

    test("another receptionist is blocked by someone else's open shift", () {
      final start = shiftStartFor(openShift: janesShift, user: tom);
      expect(start, isA<ShiftBlocked>());
      expect((start as ShiftBlocked).openShift, janesShift);
    });

    test('workWithoutShift (admin) is never forced to open a shift', () {
      expect(
        shiftStartFor(openShift: null, user: owner),
        isA<ShiftReady>().having((s) => s.shift, 'shift', isNull),
      );
      // Someone else's shift is not the admin's to use.
      expect(
        shiftStartFor(openShift: janesShift, user: owner),
        isA<ShiftReady>().having((s) => s.shift, 'shift', isNull),
      );
    });
  });

  group('required test case 17: no open shift, no money (BR-12)', () {
    test('a payment without an open shift is rejected', () {
      expect(() => requireOpenShift(null), throwsA(isA<NoOpenShift>()));
    });

    test('an open shift is returned for the payment to use', () {
      expect(requireOpenShift(janesShift), janesShift);
    });
  });

  group('required test case 13: shift takings with refunds', () {
    const cash = PaymentMethod.cash;
    const paybill = PaymentMethod.paybill;
    final at = DateTime.utc(2026, 10, 21, 12);

    /// A refund of [amount] in each lifecycle state; only `paid` ones carry
    /// a payout.
    Refund refund(String id, int amount, {PaymentMethod? paidBy, String? shift}) {
      var r = requestRefund(
        RefundTerms(nights: amount ~/ 700, pricePerNight: 700),
        id: id,
        stayId: 'stay-$id',
        by: jane,
        at: at,
      );
      if (paidBy == null) return r;
      r = approveRefund(r, by: owner, at: at);
      return payRefund(
        r,
        by: jane,
        shift: shift == null
            ? janesShift
            : OpenShift(
                id: shift,
                userId: 'jane',
                userName: 'Jane',
                openedAt: at,
                openingFloat: 0,
              ),
        method: paidBy,
        mpesaCode: paidBy == paybill ? 'CODE$id' : null,
        codeInUse: false,
        at: at,
      );
    }

    final payments = [
      (id: 'p1', amount: 2100, method: cash),
      (id: 'p2', amount: 2800, method: paybill),
      (id: 'p3', amount: 700, method: cash),
    ];

    test('received, refunded and net, for cash and M-Pesa separately', () {
      final t = takingsFrom(
        payments: payments,
        refundPayouts: refundPayoutsIn(janesShift.id, [
          refund('r1', 1400, paidBy: cash),
          refund('r2', 700, paidBy: paybill),
        ]),
      );
      expect((t.cash.received, t.cash.refunded, t.cash.net), (2800, 1400, 1400));
      expect(
        (t.paybill.received, t.paybill.refunded, t.paybill.net),
        (2800, 700, 2100),
      );
      expect((t.received, t.refunded, t.net), (5600, 2100, 3500));
    });

    test('a cash payout reduces expected cash; a Paybill payout reduces the '
        'Paybill total', () {
      final before = takingsFrom(payments: payments);
      final after = takingsFrom(
        payments: payments,
        refundPayouts: refundPayoutsIn(janesShift.id, [
          refund('r1', 1400, paidBy: cash),
          refund('r2', 700, paidBy: paybill),
        ]),
      );
      expect(before.expectedCash(openingFloat: 1000), 3800);
      expect(after.expectedCash(openingFloat: 1000), 2400);
      expect(before.expectedPaybill, 2800);
      expect(after.expectedPaybill, 2100);
    });

    test('requested and approved-but-unpaid refunds change no totals', () {
      final requestedOnly = refund('r1', 1400);
      final approvedOnly = approveRefund(refund('r2', 700), by: owner, at: at);
      expect(requestedOnly.status, RefundStatus.requested);
      expect(approvedOnly.status, RefundStatus.approved);
      final t = takingsFrom(
        payments: payments,
        refundPayouts: refundPayoutsIn(janesShift.id, [
          requestedOnly,
          approvedOnly,
        ]),
      );
      expect((t.refunded, t.net), (0, 5600));
    });

    test('a payout counts only in the shift that paid it', () {
      final t = takingsFrom(
        payments: const [],
        refundPayouts: refundPayoutsIn(janesShift.id, [
          refund('r1', 1400, paidBy: cash, shift: 'other-shift'),
        ]),
      );
      expect(t.refunded, 0);
    });

    test('voided payments and voided payouts are excluded', () {
      final t = takingsFrom(
        payments: payments,
        refundPayouts: refundPayoutsIn(janesShift.id, [
          refund('r1', 1400, paidBy: cash),
          refund('r2', 700, paidBy: paybill),
        ]),
        voidedPaymentIds: const {'p2'},
        voidedRefundIds: const {'r1'},
      );
      expect((t.cash.received, t.cash.refunded), (2800, 0));
      expect((t.paybill.received, t.paybill.refunded), (0, 700));
      expect(t.net, 2100);
    });

    test('no money is zero', () {
      final t = takingsFrom(payments: const []);
      expect((t.received, t.refunded, t.net), (0, 0, 0));
    });
  });
}
