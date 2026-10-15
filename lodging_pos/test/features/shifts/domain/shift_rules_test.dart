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

    test('a receptionist is asked to resume their own open shift', () {
      final start = shiftStartFor(
        openShift: janesShift,
        userId: 'jane',
        role: Role.receptionist,
      );
      expect(start, isA<ResumeShift>());
      expect((start as ResumeShift).shift, janesShift);
    });

    test('once they continue it, they are ready to work', () {
      final start = shiftStartFor(
        openShift: janesShift,
        userId: 'jane',
        role: Role.receptionist,
        resumeConfirmed: true,
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

  group('takingsFrom (BR-11, required test case 12)', () {
    test('totals cash and Paybill separately', () {
      final t = takingsFrom([
        (id: 'p1', amount: 700, method: 'cash'),
        (id: 'p2', amount: 1000, method: 'paybill'),
        (id: 'p3', amount: 500, method: 'cash'),
      ], voidedIds: const {});
      expect((t.cash, t.paybill, t.total), (1200, 1000, 2200));
    });

    test('a voided payment is excluded from the shift totals', () {
      final t = takingsFrom(
        [
          (id: 'p1', amount: 700, method: 'cash'),
          (id: 'p2', amount: 1000, method: 'paybill'),
        ],
        voidedIds: const {'p2'},
      );
      expect((t.cash, t.paybill, t.total), (700, 0, 700));
    });

    test('no payments is zero', () {
      final t = takingsFrom(const [], voidedIds: const {});
      expect(t.total, 0);
    });
  });
}
