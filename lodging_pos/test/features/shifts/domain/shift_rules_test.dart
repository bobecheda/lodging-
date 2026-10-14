import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/shifts/domain/shift.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';

void main() {
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
        shiftStartFor(openShift: null, userId: 'jane', role: Role.receptionist),
        isA<OpenNewShift>(),
      );
    });

    test('a receptionist resumes their own open shift', () {
      final start = shiftStartFor(
        openShift: janesShift,
        userId: 'jane',
        role: Role.receptionist,
      );
      expect(start, isA<ShiftReady>());
      expect((start as ShiftReady).shift, janesShift);
    });

    test("another receptionist is blocked by someone else's open shift", () {
      final start = shiftStartFor(
        openShift: janesShift,
        userId: 'tom',
        role: Role.receptionist,
      );
      expect(start, isA<ShiftBlocked>());
      expect((start as ShiftBlocked).openShift, janesShift);
    });

    test('an admin is never forced to open a shift', () {
      expect(
        shiftStartFor(openShift: null, userId: 'owner', role: Role.admin),
        isA<ShiftReady>().having((s) => s.shift, 'shift', isNull),
      );
      // Someone else's shift is not the admin's to use.
      expect(
        shiftStartFor(openShift: janesShift, userId: 'owner', role: Role.admin),
        isA<ShiftReady>().having((s) => s.shift, 'shift', isNull),
      );
    });
  });

  group('requireOpenShift (BR-12)', () {
    // Required test case 10: payment without an open shift is rejected.
    test('payment without an open shift is rejected', () {
      expect(() => requireOpenShift(null), throwsA(isA<NoOpenShift>()));
    });

    test('an open shift is returned for the payment to use', () {
      expect(requireOpenShift(janesShift), janesShift);
    });
  });
}
