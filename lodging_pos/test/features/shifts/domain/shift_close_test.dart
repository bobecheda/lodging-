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

  group('the note', () {
    test('needed when the cash is short or over; at most 200 characters', () {
      expect(closeNoteError('', 0), isNull);
      expect(closeNoteError('   ', -200), 'Say why the cash is short.');
      expect(closeNoteError('', 50), 'Say why the cash is over.');
      expect(closeNoteError('Gave KES 200 too much change', -200), isNull);
      expect(closeNoteError('x' * 201, -200), 'Use at most 200 characters.');
      expect(closeNoteError('x' * 200, -200), isNull);
    });
  });

  group('the owner’s Shifts screen', () {
    test('a variance over 1% of the shift’s takings is highlighted', () {
      expect(highVariance(-50, takings: 5000), isFalse); // exactly 1%
      expect(highVariance(-51, takings: 5000), isTrue);
      expect(highVariance(0, takings: 0), isFalse);
      expect(highVariance(20, takings: 0), isTrue);
    });

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

  test('closeChange: a payment since the review stops the close', () {
    expect(closeChange(takings(cash: 4000), takings(cash: 4000)), isNull);
    expect(
      closeChange(takings(cash: 4000), takings(cash: 4700)),
      'A payment came in since you counted. Check the figures and close '
      'again.',
    );
  });
}
