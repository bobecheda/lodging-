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
  final owner = user(Role.owner);
  final supervisor = user(Role.supervisor);
  final desk = user(Role.receptionist);

  group('required test case 18: the permission map (BR-13)', () {
    test('a receptionist cannot edit prices, void, manage users or approve '
        'refunds; the supervisor voids and manages users; only the owner '
        'edits prices and approves refunds', () {
      for (final p in [
        Permission.editPrices,
        Permission.voidRecords,
        Permission.manageUsers,
        Permission.approveRefund,
      ]) {
        expect(can(desk, p), isFalse, reason: '$p');
        expect(() => requirePermission(desk, p), throwsA(isA<NotPermitted>()));
      }
      for (final p in [Permission.voidRecords, Permission.manageUsers]) {
        expect(can(supervisor, p), isTrue, reason: '$p');
        requirePermission(supervisor, p);
      }
      for (final p in [Permission.editPrices, Permission.approveRefund]) {
        expect(can(supervisor, p), isFalse, reason: '$p');
        expect(can(owner, p), isTrue, reason: '$p');
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

  test('the map as agreed with the owner (21 Oct 2026; owner sign-in)', () {
    const ownerOnly = {
      Permission.editPrices,
      Permission.approveRefund,
      Permission.decidePriceChange,
      Permission.viewBusinessDashboard,
      Permission.manageSupervisors,
    };
    const ownerAndSupervisor = {
      Permission.viewAllReports,
      Permission.viewAuditTrail,
      Permission.workWithoutShift,
    };
    const supervisorOnly = {
      Permission.requestPriceChange,
      Permission.closeOtherShifts,
      Permission.manageBackups,
      Permission.manageRooms,
      Permission.editSettings,
      Permission.manageUsers,
      Permission.manageHousekeepers,
      Permission.voidRecords,
      Permission.manageInventoryItems,
      Permission.recordExpenses,
    };
    const desk = {
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
      Permission.printReceipts,
    };
    expect({
      ...ownerOnly,
      ...ownerAndSupervisor,
      ...supervisorOnly,
      ...desk,
    }, Permission.values.toSet());
    for (final p in ownerOnly) {
      expect(permissionMap[p], {Role.owner}, reason: '$p');
    }
    for (final p in ownerAndSupervisor) {
      expect(permissionMap[p], {Role.owner, Role.supervisor}, reason: '$p');
    }
    for (final p in supervisorOnly) {
      expect(permissionMap[p], {Role.supervisor}, reason: '$p');
    }
    for (final p in desk) {
      expect(permissionMap[p], {
        Role.supervisor,
        Role.receptionist,
      }, reason: '$p');
    }
  });

  test('the owner works from the business view, never the desk, and is '
      'never asked to open a shift', () {
    for (final p in [
      Permission.checkIn,
      Permission.openShift,
      Permission.payRefund,
    ]) {
      expect(can(owner, p), isFalse, reason: '$p');
    }
    expect(can(owner, Permission.workWithoutShift), isTrue);
  });

  test('a disabled user can do nothing', () {
    final disabled = user(Role.supervisor, isActive: false);
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
