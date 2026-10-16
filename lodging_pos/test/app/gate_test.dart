import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/shifts/domain/shift.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';

void main() {
  const desk = UserAccount(
    id: 'u1',
    fullName: 'Desk',
    username: 'desk',
    role: Role.receptionist,
    isActive: true,
    mustChangePassword: false,
  );
  final shift = OpenShift(
    id: 's1',
    userId: 'u1',
    userName: 'Desk',
    openedAt: DateTime.utc(2026, 10, 14),
    openingFloat: 0,
  );

  String? go(
    String location, {
    bool? hasUsers = true,
    UserAccount? user = desk,
    ShiftStart? shiftStart,
  }) => redirectFor(
    location,
    hasUsers: hasUsers,
    user: user,
    shiftStart: shiftStart ?? ShiftReady(shift),
  );

  test('waits on the splash screen while loading', () {
    expect(go(Routes.login, hasUsers: null), Routes.splash);
    expect(
      redirectFor(Routes.home, hasUsers: true, user: desk, shiftStart: null),
      Routes.splash,
    );
  });

  test('no users: only setup is reachable', () {
    for (final location in [Routes.login, Routes.home, Routes.shift, '/x']) {
      expect(go(location, hasUsers: false, user: null), Routes.setup);
    }
    expect(go(Routes.setup, hasUsers: false, user: null), isNull);
  });

  test('once a user exists, setup is unreachable', () {
    expect(go(Routes.setup, user: null), Routes.login);
    expect(go(Routes.setup), Routes.home);
  });

  test('signed out: login only', () {
    expect(go(Routes.home, user: null), Routes.login);
    expect(go(Routes.login, user: null), isNull);
  });

  test('must change password: nothing else is reachable', () {
    final fresh = desk.copyWith(mustChangePassword: true);
    for (final location in [Routes.home, Routes.shift, Routes.login, '/x']) {
      expect(go(location, user: fresh), Routes.changePassword);
    }
    expect(go(Routes.changePassword, user: fresh), isNull);
  });

  test('a receptionist without a usable shift goes to the shift screen', () {
    expect(go(Routes.home, shiftStart: const OpenNewShift()), Routes.shift);
    expect(go(Routes.home, shiftStart: ShiftBlocked(shift)), Routes.shift);
    expect(go(Routes.shift, shiftStart: const OpenNewShift()), isNull);
  });

  test('ready: gates send you home, working screens stay', () {
    expect(go(Routes.login), Routes.home);
    expect(go(Routes.shift), Routes.home);
    expect(go(Routes.home), isNull);
    expect(go('/bed-board'), isNull);
  });

  test(
    'owner-only screens (AD-1): the owner stays, a receptionist goes home',
    () {
      const owner = UserAccount(
        id: 'o1',
        fullName: 'Owner',
        username: 'owner',
        role: Role.admin,
        isActive: true,
        mustChangePassword: false,
      );
      expect(
        redirectFor(
          Routes.adminRooms,
          hasUsers: true,
          user: owner,
          shiftStart: const ShiftReady(null),
        ),
        isNull,
      );
      expect(go(Routes.adminRooms), Routes.home);
      expect(
        redirectFor(
          Routes.adminPrices,
          hasUsers: true,
          user: owner,
          shiftStart: const ShiftReady(null),
        ),
        isNull,
      );
      expect(go(Routes.adminPrices), Routes.home);
      expect(go('/admin/not-yet-built'), Routes.home); // fails closed
      expect(go('/admin'), Routes.home);
      expect(go('/administrator'), isNull); // not under the prefix
    },
  );
}
