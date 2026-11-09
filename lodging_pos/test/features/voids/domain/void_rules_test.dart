import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/voids/domain/void_rules.dart';

const owner = UserAccount(
  id: 'owner',
  fullName: 'Amina Owner',
  username: 'owner',
  role: Role.owner,
  isActive: true,
  mustChangePassword: false,
);

const supervisor = UserAccount(
  id: 'supervisor',
  fullName: 'Grace Supervisor',
  username: 'supervisor',
  role: Role.supervisor,
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

VoidPayment payment(
  String id, {
  required List<String> stays,
  String by = 'desk',
  int amount = 700,
  bool voided = false,
}) => VoidPayment(
  id: id,
  receiptNumber: 'R-${id.padLeft(6, '0')}',
  amount: amount,
  receivedBy: by,
  stayIds: stays,
  voided: voided,
);

VoidStay stay(
  String id, {
  required List<String> payments,
  String bed = 'A',
  String by = 'desk',
  bool active = true,
  bool refund = false,
  bool voided = false,
}) => VoidStay(
  id: id,
  roomNumber: '4',
  bedLabel: bed,
  checkedInBy: by,
  isActive: active,
  paymentIds: payments,
  hasRefund: refund,
  voided: voided,
);

/// One guest, one bed: check-in payment 1, extension payment 2.
VoidFacts oneBed({
  String checkedInBy = 'desk',
  String extendedBy = 'desk',
  bool active = true,
  bool refund = false,
}) => VoidFacts(
  payments: [
    payment('1', stays: ['s-a'], by: checkedInBy),
    payment('2', stays: ['s-a'], by: extendedBy, amount: 1400),
  ],
  stays: [
    stay(
      's-a',
      payments: ['1', '2'],
      by: checkedInBy,
      active: active,
      refund: refund,
    ),
  ],
);

void main() {
  group('the permission (BR-11, BR-13)', () {
    test('the owner and the supervisor void; a receptionist does not', () {
      expect(can(owner, Permission.voidRecords), isTrue);
      expect(can(supervisor, Permission.voidRecords), isTrue);
      expect(can(desk, Permission.voidRecords), isFalse);
    });

    test('a receptionist is refused by the check itself', () {
      final plan = paymentVoidPlan(oneBed(), '1');
      expect(
        () => checkVoid(plan, by: desk, reason: 'Wrong method'),
        throwsA(isA<NotPermitted>()),
      );
    });

    test('a disabled supervisor may not void', () {
      final plan = paymentVoidPlan(oneBed(), '1');
      expect(
        () => checkVoid(
          plan,
          by: supervisor.copyWith(isActive: false),
          reason: 'Wrong method',
        ),
        throwsA(isA<NotPermitted>()),
      );
    });
  });

  group('the reason', () {
    test('is required and trimmed', () {
      expect(voidReasonError(''), 'Say why it is being voided.');
      expect(voidReasonError('   '), 'Say why it is being voided.');
      expect(voidReasonError('  Wrong method  '), isNull);
      final plan = paymentVoidPlan(oneBed(), '1');
      expect(
        () => checkVoid(plan, by: supervisor, reason: ' '),
        throwsA(
          isA<VoidRuleViolation>().having(
            (e) => e.message,
            'message',
            'Say why it is being voided.',
          ),
        ),
      );
      expect(cleanVoidReason('  Wrong method '), 'Wrong method');
    });

    test('is at most 200 characters', () {
      expect(voidReasonError('x' * voidReasonMax), isNull);
      expect(
        voidReasonError('x' * (voidReasonMax + 1)),
        'Keep the reason to 200 characters.',
      );
    });
  });

  group('nobody voids their own record', () {
    test('the payment\'s taker can\'t void it; someone else can', () {
      final plan = paymentVoidPlan(oneBed(extendedBy: 'supervisor'), '2');
      expect(
        voidBlocker(plan, supervisor),
        'You took R-000002 yourself, so someone else must void it.',
      );
      expect(voidBlocker(plan, owner), isNull);
      expect(
        () => checkVoid(plan, by: supervisor, reason: 'Wrong method'),
        throwsA(isA<VoidRuleViolation>()),
      );
    });

    test('the guest\'s check-in clerk can\'t void the stay', () {
      final plan = stayVoidPlan(oneBed(checkedInBy: 'supervisor'), 's-a');
      expect(
        voidBlocker(plan, supervisor),
        'You checked Room 4 · Bed A in yourself, so someone else must void '
        'it.',
      );
      expect(voidBlocker(plan, owner), isNull);
    });

    test('a stay with a payment the voider took is theirs too', () {
      final plan = stayVoidPlan(oneBed(extendedBy: 'supervisor'), 's-a');
      expect(
        voidBlocker(plan, supervisor),
        'You took R-000002 yourself, so someone else must void this stay.',
      );
    });
  });

  group('a void can\'t be voided or repeated', () {
    test('an already voided payment', () {
      final facts = VoidFacts(
        payments: [
          payment('1', stays: ['s-a'], voided: true),
        ],
        stays: [
          stay('s-a', payments: ['1']),
        ],
      );
      expect(
        voidBlocker(paymentVoidPlan(facts, '1'), supervisor),
        'R-000001 has already been voided.',
      );
    });

    test('an already voided stay', () {
      final facts = VoidFacts(
        payments: [
          payment('1', stays: ['s-a'], voided: true),
        ],
        stays: [
          stay('s-a', payments: ['1'], active: false, voided: true),
        ],
      );
      expect(
        voidBlocker(stayVoidPlan(facts, 's-a'), supervisor),
        'Room 4 · Bed A has already been voided.',
      );
    });

    test('there is no target type for a void: only payments and stays', () {
      expect(VoidTarget.values.map((t) => t.code), ['payment', 'stay']);
    });
  });

  group('refunds', () {
    test('a stay with a refund can\'t be voided, nor its payments', () {
      final facts = oneBed(active: false, refund: true);
      const message =
          'Room 4 · Bed A has a refund, so it can\'t be voided here. Write '
          'the correction in the corrections book.';
      expect(voidBlocker(stayVoidPlan(facts, 's-a'), supervisor), message);
      expect(voidBlocker(paymentVoidPlan(facts, '1'), supervisor), message);
    });
  });

  group('what a payment void covers', () {
    test('only the payment; an active stay it paid is left in use', () {
      final plan = paymentVoidPlan(oneBed(), '2');
      expect([for (final p in plan.payments) p.id], ['2']);
      expect(plan.stays, isEmpty);
      expect(plan.amount, 1400);
      expect([for (final s in plan.staysLeftInUse) s.id], ['s-a']);
      expect(voidBlocker(plan, supervisor), isNull);
    });

    test('a closed stay\'s payment leaves nothing in use', () {
      final plan = paymentVoidPlan(oneBed(active: false), '1');
      expect(plan.staysLeftInUse, isEmpty);
    });
  });

  group('what a stay void covers', () {
    test('the stay and every payment it has not yet voided', () {
      final facts = VoidFacts(
        payments: [
          payment('1', stays: ['s-a']),
          payment('2', stays: ['s-a'], voided: true),
          payment('3', stays: ['s-a'], amount: 700),
        ],
        stays: [
          stay('s-a', payments: ['1', '2', '3']),
        ],
      );
      final plan = stayVoidPlan(facts, 's-a');
      expect([for (final s in plan.stays) s.id], ['s-a']);
      expect([for (final p in plan.payments) p.id], ['1', '3']);
      expect(plan.amount, 1400);
      expect([for (final s in plan.staysToClose) s.id], ['s-a']);
      expect(plan.staysLeftInUse, isEmpty);
    });

    test('one payment for both beds: both stays go, as one booking (BR-4)', () {
      final facts = VoidFacts(
        payments: [
          payment('1', stays: ['s-a', 's-b'], amount: 1300),
          payment('2', stays: ['s-b'], amount: 600),
        ],
        stays: [
          stay('s-a', payments: ['1']),
          stay('s-b', bed: 'B', payments: ['1', '2'], active: false),
        ],
      );
      final plan = stayVoidPlan(facts, 's-a');
      expect([for (final s in plan.stays) s.id], ['s-a', 's-b']);
      expect([for (final p in plan.payments) p.id], ['1', '2']);
      expect([for (final s in plan.staysToClose) s.id], ['s-a']);
      expect(plan.amount, 1900);
    });

    test('a voided payment no longer ties two stays together', () {
      final facts = VoidFacts(
        payments: [
          payment('1', stays: ['s-a', 's-b'], voided: true),
          payment('2', stays: ['s-a']),
        ],
        stays: [
          stay('s-a', payments: ['1', '2']),
          stay('s-b', bed: 'B', payments: ['1']),
        ],
      );
      final plan = stayVoidPlan(facts, 's-a');
      expect([for (final s in plan.stays) s.id], ['s-a']);
      expect([for (final p in plan.payments) p.id], ['2']);
    });

    test('a refund on the other bed of the booking blocks the whole void', () {
      final facts = VoidFacts(
        payments: [
          payment('1', stays: ['s-a', 's-b']),
        ],
        stays: [
          stay('s-a', payments: ['1']),
          stay('s-b', bed: 'B', payments: ['1'], active: false, refund: true),
        ],
      );
      expect(
        voidBlocker(stayVoidPlan(facts, 's-a'), supervisor),
        startsWith('Room 4 · Bed B has a refund'),
      );
    });
  });

  test('the confirmation says what goes', () {
    final facts = VoidFacts(
      payments: [
        payment('1', stays: ['s-a', 's-b'], amount: 1300),
      ],
      stays: [
        stay('s-a', payments: ['1']),
        stay('s-b', bed: 'B', payments: ['1']),
      ],
    );
    expect(
      stayVoidPlan(facts, 's-a').summary,
      'Voids Room 4 · Bed A and Room 4 · Bed B, and R-000001 (KES 1,300). '
      'Both beds become available and need cleaning.',
    );
    expect(
      paymentVoidPlan(oneBed(), '2').summary,
      'Voids R-000002 (KES 1,400). Room 4 · Bed A stays in use, with nights '
      'no money is behind. To correct a wrong method or M-Pesa code, void '
      'the stay instead, mark the bed clean and check the guest in again.',
    );
    expect(
      paymentVoidPlan(oneBed(active: false), '1').summary,
      'Voids R-000001 (KES 700).',
    );
  });
}
