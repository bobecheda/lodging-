import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/shifts/domain/shift_close.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';

UserAccount user(String id, Role role) => UserAccount(
  id: id,
  fullName: id,
  username: id,
  role: role,
  isActive: true,
  mustChangePassword: false,
);

ShiftTakings takings({int cash = 0, int paybill = 0, int cashOut = 0}) =>
    takingsFrom(
      payments: [
        if (cash > 0) (id: 'c', amount: cash, method: PaymentMethod.cash),
        if (paybill > 0)
          (id: 'p', amount: paybill, method: PaymentMethod.paybill),
      ],
      refundPayouts: [
        if (cashOut > 0) (id: 'r', amount: cashOut, method: PaymentMethod.cash),
      ],
    );

void main() {
  group('the close figures (FD-11)', () {
    test('expected cash is the float plus net cash; M-Pesa is net M-Pesa', () {
      final f = closeFigures(
        takings(cash: 4000, paybill: 1400, cashOut: 0),
        openingFloat: 1000,
        firstCount: 4800,
        counted: 4800,
      );
      expect((f.expectedCash, f.expectedPaybill), (5000, 1400));
      expect(f.variance, -200);
    });

    test('a cash refund payout lowers expected cash (BR-8b)', () {
      final f = closeFigures(
        takings(cash: 4000, cashOut: 700),
        openingFloat: 1000,
        firstCount: 4300,
        counted: 4300,
      );
      expect((f.expectedCash, f.variance), (4300, 0));
    });
  });

  test('variance wording', () {
    expect(varianceLabel(0), 'Exact');
    expect(varianceLabel(-200), 'Short KES 200');
    expect(varianceLabel(50), 'Over KES 50');
  });

  test('the count: whole KES, zero or more', () {
    expect(countError(0), isNull);
    expect(countError(4800), isNull);
    expect(countError(null), 'Enter the cash you counted.');
    expect(countError(-1), 'The count cannot be negative.');
  });

  group('the blind count (FD-11, Story B)', () {
    test('a count matches only within the tolerance (UB40: 0, overs too)', () {
      expect(countMatches(5000, expected: 5000), isTrue);
      expect(countMatches(4999, expected: 5000), isFalse);
      expect(countMatches(5001, expected: 5000), isFalse);
      expect(countMatches(4950, expected: 5000, tolerance: 50), isTrue);
      expect(countMatches(4949, expected: 5000, tolerance: 50), isFalse);
      expect(countMatches(5050, expected: 5000, tolerance: 50), isTrue);
    });

    test('the stage: first count, one recount, then a reason', () {
      expect(countStage(firstCount: null, recount: null), CountStage.first);
      expect(countStage(firstCount: 4800, recount: null), CountStage.recount);
      expect(countStage(firstCount: 4800, recount: 4800), CountStage.reason);
    });

    test('what the counter is told: never an amount, never short or over', () {
      for (final message in [countAgainMessage, reasonNeededMessage]) {
        expect(message, isNot(matches(RegExp(r'\d'))));
        expect(message.toLowerCase(), isNot(contains('short')));
        expect(message.toLowerCase(), isNot(contains('over')));
        expect(message, isNot(contains('KES')));
      }
      expect(
        countAgainMessage,
        'Your count doesn’t match. Count the cash again.',
      );
      expect(
        reasonNeededMessage,
        'Your count still doesn’t match. Say why, then close the shift.',
      );
    });

    test('the reason: required, at most 200 characters, in neutral words', () {
      expect(closeReasonError(''), 'Say why the count may be different.');
      expect(closeReasonError('   '), 'Say why the count may be different.');
      expect(closeReasonError('Gave change from my pocket'), isNull);
      expect(closeReasonError('x' * 200), isNull);
      expect(closeReasonError('x' * 201), 'Use at most 200 characters.');
    });

    test('matched only on recount: the first count differed, the final '
        'matched', () {
      expect(
        matchedOnRecount(firstCount: 4800, counted: 5000, needsReview: false),
        isTrue,
      );
      expect(
        matchedOnRecount(firstCount: 5000, counted: 5000, needsReview: false),
        isFalse,
      );
      expect(
        matchedOnRecount(firstCount: 4800, counted: 4800, needsReview: true),
        isFalse,
      );
    });
  });

  group('the supervisor’s Shifts screen', () {
    test('a recount shows both counts', () {
      expect(recountLine(5000, 5000), isNull);
      expect(
        recountLine(4800, 5000),
        'first count KES 4,800 → recounted KES 5,000',
      );
    });

    test('someone else’s close says who did it', () {
      expect(
        closedByLine(closer: 'Mary Wanjiku', owner: 'Mary Wanjiku'),
        isNull,
      );
      expect(
        closedByLine(closer: 'Grace Supervisor', owner: 'Mary Wanjiku'),
        'closed by Grace Supervisor for Mary Wanjiku’s shift',
      );
    });
  });

  group('who may close a shift (BR-13)', () {
    final desk = user('mary', Role.receptionist);
    final supervisor = user('grace', Role.supervisor);

    test('your own: anyone with closeShift', () {
      expect(mayCloseShift(desk, shiftUserId: 'mary'), isTrue);
      expect(mayCloseShift(supervisor, shiftUserId: 'grace'), isTrue);
    });

    test('someone else’s: closeOtherShifts (supervisor for now)', () {
      expect(mayCloseShift(supervisor, shiftUserId: 'mary'), isTrue);
      expect(mayCloseShift(desk, shiftUserId: 'tom'), isFalse);
      expect(can(supervisor, Permission.closeOtherShifts), isTrue);
      expect(can(desk, Permission.closeOtherShifts), isFalse);
    });
  });
}
