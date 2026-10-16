import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/refunds/domain/refund.dart';
import 'package:lodging_pos/features/shifts/domain/shift.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

DateTime oct(int day, int hour, [int minute = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute);

const owner = UserAccount(
  id: 'owner',
  fullName: 'Grace Owner',
  username: 'owner',
  role: Role.admin,
  isActive: true,
  mustChangePassword: false,
);

const desk = UserAccount(
  id: 'desk',
  fullName: 'Desk Clerk',
  username: 'desk',
  role: Role.receptionist,
  isActive: true,
  mustChangePassword: false,
);

final shift = OpenShift(
  id: 'shift-1',
  userId: 'desk',
  userName: 'Desk Clerk',
  openedAt: oct(21, 6),
  openingFloat: 500,
);

/// 3 unused nights at 700, requested at Wed 15:00 checkout.
Refund requested() => requestRefund(
  RefundTerms(nights: 3, pricePerNight: 700),
  id: 'refund-1',
  stayId: 'stay-1',
  by: desk,
  at: oct(21, 15),
);

Refund approved() => approveRefund(requested(), by: owner, at: oct(21, 16));

Refund pay(
  Refund refund, {
  UserAccount by = desk,
  OpenShift? shift,
  PaymentMethod method = PaymentMethod.cash,
  String? mpesaCode,
  bool codeInUse = false,
}) => payRefund(
  refund,
  by: by,
  shift: shift,
  method: method,
  mpesaCode: mpesaCode,
  codeInUse: codeInUse,
  at: oct(21, 17),
);

Matcher violates(String message) => throwsA(
  isA<RefundRuleViolation>().having((e) => e.message, 'message', message),
);

void main() {
  group('required test case 12: refund lifecycle', () {
    test('a new request is "requested", for the calculated amount', () {
      final r = requested();
      expect(r.status, RefundStatus.requested);
      expect((r.nights, r.pricePerNight, r.amount), (3, 700, 2100));
      expect((r.requestedBy, r.requestedAt), ('desk', oct(21, 15)));
      expect(r.decision, isNull);
      expect(r.payout, isNull);
    });

    test('a receptionist cannot approve or reject', () {
      expect(
        () => approveRefund(requested(), by: desk, at: oct(21, 16)),
        throwsA(
          isA<NotPermitted>().having(
            (e) => e.permission,
            'permission',
            Permission.approveRefund,
          ),
        ),
      );
      expect(
        () => rejectRefund(
          requested(),
          by: desk,
          note: 'No',
          at: oct(21, 16),
        ),
        throwsA(isA<NotPermitted>()),
      );
    });

    test('the admin approves → "approved"', () {
      final r = approved();
      expect(r.status, RefundStatus.approved);
      expect(r.decision!.kind, RefundDecisionKind.approved);
      expect(r.decision!.decidedBy, 'owner');
      expect(r.decision!.decidedAt, oct(21, 16));
    });

    test('the admin rejects only with a reason', () {
      for (final note in [null, '', '   ']) {
        expect(
          () => rejectRefund(
            requested(),
            by: owner,
            note: note,
            at: oct(21, 16),
          ),
          violates('Give a reason for rejecting the refund.'),
          reason: '"$note"',
        );
      }
      final r = rejectRefund(
        requested(),
        by: owner,
        note: ' Guest damaged the bed ',
        at: oct(21, 16),
      );
      expect(r.status, RefundStatus.rejected);
      expect(r.decision!.note, 'Guest damaged the bed');
    });

    test('a refund is decided once', () {
      expect(
        () => approveRefund(approved(), by: owner, at: oct(21, 18)),
        violates('This refund has already been decided.'),
      );
      expect(
        () => rejectRefund(approved(), by: owner, note: 'x', at: oct(21, 18)),
        violates('This refund has already been decided.'),
      );
    });

    test('payout before approval is refused, and never after a rejection', () {
      expect(
        () => pay(requested(), shift: shift),
        violates('This refund has not been approved yet.'),
      );
      final rejected = rejectRefund(
        requested(),
        by: owner,
        note: 'Damage',
        at: oct(21, 16),
      );
      expect(
        () => pay(rejected, shift: shift),
        violates('This refund was rejected.'),
      );
    });

    test('payout after approval → "paid", in the paying shift', () {
      final r = pay(approved(), shift: shift);
      expect(r.status, RefundStatus.paid);
      final payout = r.payout!;
      expect(payout.method, PaymentMethod.cash);
      expect(payout.mpesaCode, isNull);
      expect(payout.shiftId, 'shift-1');
      expect(payout.paidBy, 'desk');
      expect(payout.paidAt, oct(21, 17));
    });

    test('a second payout is refused', () {
      final paid = pay(approved(), shift: shift);
      expect(
        () => pay(paid, shift: shift),
        violates('This refund has already been paid.'),
      );
    });

    test('nobody can change the amount', () {
      // Approving and paying take no amount: it stays what the rules
      // calculated at checkout.
      final paid = pay(approved(), shift: shift);
      expect(
        (paid.nights, paid.pricePerNight, paid.amount),
        (3, 700, 2100),
      );
      expect(RefundTerms(nights: 3, pricePerNight: 700).amount, 2100);
    });

    test('an admin can pay too; a Paybill payout needs an unused code', () {
      expect(
        () => pay(approved(), shift: shift, method: PaymentMethod.paybill),
        throwsA(isA<InvalidMpesaCode>()),
      );
      expect(
        () => pay(
          approved(),
          shift: shift,
          method: PaymentMethod.paybill,
          mpesaCode: 'SJK4H7XQ2P',
          codeInUse: true,
        ),
        throwsA(isA<InvalidMpesaCode>()),
      );
      final r = pay(
        approved(),
        by: owner,
        shift: shift,
        method: PaymentMethod.paybill,
        mpesaCode: ' sjk4h7xq2p ',
      );
      expect(r.payout!.mpesaCode, 'SJK4H7XQ2P');
      expect(r.payout!.paidBy, 'owner');
    });

    test('requesting needs the requestRefund permission and nights to '
        'refund', () {
      final inactive = desk.copyWith(isActive: false);
      expect(
        () => requestRefund(
          RefundTerms(nights: 3, pricePerNight: 700),
          id: 'r',
          stayId: 's',
          by: inactive,
          at: oct(21, 15),
        ),
        throwsA(isA<NotPermitted>()),
      );
      expect(
        () => RefundTerms(nights: 0, pricePerNight: 700),
        throwsArgumentError,
      );
    });
  });

  test('required test case 17: a refund payout without an open shift is '
      'rejected', () {
    expect(() => pay(approved(), shift: null), throwsA(isA<NoOpenShift>()));
  });

  test('the early-checkout calculation becomes the request', () {
    // 10 nights from Thu 19:00, leaving Wed 15:00: 3 nights back.
    final plan = planCheckIn(
      checkInAt: oct(15, 19),
      nights: 10,
      checkout: const ClockTime(10, 0),
      beds: [(bedId: 'b', pricePerNight: 700)],
    );
    final stay = Stay.fromCheckIn(
      id: 'stay-1',
      bedId: 'b',
      charge: plan.stays.single.charge,
    );
    final terms = earlyCheckoutRefund(stay, oct(21, 15), 60)!;
    final r = requestRefund(
      terms,
      id: 'refund-1',
      stayId: stay.id,
      by: desk,
      at: oct(21, 15),
    );
    expect(r.amount, 2100);
  });
}
