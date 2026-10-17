import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';

UserAccount user(Role role, {bool isActive = true}) => UserAccount(
  id: role.name,
  fullName: role.name,
  username: role.name,
  role: role,
  isActive: isActive,
  mustChangePassword: false,
);

void main() {
  final admin = user(Role.admin);
  final desk = user(Role.receptionist);

  group('required test case 18: the permission map (BR-13)', () {
    test('a receptionist cannot edit prices, void, manage users or approve '
        'refunds; the admin can', () {
      for (final p in [
        Permission.editPrices,
        Permission.voidRecords,
        Permission.manageUsers,
        Permission.approveRefund,
      ]) {
        expect(can(desk, p), isFalse, reason: '$p');
        expect(() => requirePermission(desk, p), throwsA(isA<NotPermitted>()));
        expect(can(admin, p), isTrue, reason: '$p');
        requirePermission(admin, p);
      }
    });

    test('every Permission is assigned to at least one role', () {
      for (final p in Permission.values) {
        expect(permissionMap[p], isNotNull, reason: '$p is missing');
        expect(permissionMap[p], isNotEmpty, reason: '$p has no role');
      }
    });

    test('features call the map, never compare roles', () {
      // Enforced across lib/ by test/policy/no_role_checks_test.dart.
      expect(can(desk, Permission.checkIn), isTrue);
    });
  });

  test('the map as agreed with the owner', () {
    const adminOnly = {
      Permission.manageRooms,
      Permission.editPrices,
      Permission.editSettings,
      Permission.manageUsers,
      Permission.manageHousekeepers,
      Permission.voidRecords,
      Permission.workWithoutShift,
      Permission.approveRefund,
      Permission.viewAllReports,
      Permission.viewAuditTrail,
      Permission.manageInventoryItems,
      Permission.recordExpenses,
    };
    const everyone = {
      Permission.openShift,
      Permission.closeShift,
      Permission.checkIn,
      Permission.extendStay,
      Permission.checkOut,
      Permission.requestRefund,
      Permission.payRefund,
      Permission.assignHousekeeping,
      Permission.markClean,
      Permission.recordStock,
      Permission.viewOwnReport,
      Permission.registerGuests,
    };
    expect({...adminOnly, ...everyone}, Permission.values.toSet());
    for (final p in adminOnly) {
      expect(permissionMap[p], {Role.admin}, reason: '$p');
    }
    for (final p in everyone) {
      expect(permissionMap[p], {Role.admin, Role.receptionist}, reason: '$p');
    }
  });

  test('a disabled user can do nothing', () {
    final disabled = user(Role.admin, isActive: false);
    for (final p in Permission.values) {
      expect(can(disabled, p), isFalse, reason: '$p');
    }
    expect(
      () => requirePermission(disabled, Permission.checkIn),
      throwsA(
        isA<NotPermitted>().having(
          (e) => e.permission,
          'permission',
          Permission.checkIn,
        ),
      ),
    );
  });
}
