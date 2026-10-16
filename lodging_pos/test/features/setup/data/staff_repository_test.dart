import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/auth/data/login_service.dart';
import 'package:lodging_pos/features/auth/domain/login.dart';
import 'package:lodging_pos/features/setup/data/staff_repository.dart';
import 'package:lodging_pos/features/setup/domain/staff.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late StaffRepository staff;
  late UserAccount owner;

  setUp(() async {
    env = TestEnv();
    staff = StaffRepository(env.db, env.audit, env.hasher);
    owner = await env.users.createFirstAdmin(testSetup);
  });
  tearDown(() => env.close());

  Future<UserAccount> addMary() => staff.addReceptionist(
    owner,
    const NewReceptionist(
      fullName: ' Mary Wanjiku ',
      username: 'Mary',
      temporaryPassword: 'temp-pass-1',
    ),
  );

  Future<UserAccount> reload(String id) async =>
      (await staff.users()).firstWhere((u) => u.account.id == id).account;

  Map<String, Object?> json(String text) =>
      jsonDecode(text) as Map<String, Object?>;

  LoginService login() => LoginService(env.users, env.hasher, env.audit);

  group('receptionists', () {
    test(
      'added as a receptionist who must set a password (user.create)',
      () async {
        final mary = await addMary();
        expect(
          (mary.fullName, mary.username, mary.role),
          ('Mary Wanjiku', 'mary', Role.receptionist),
        );
        expect(mary.mustChangePassword, isTrue);
        expect(userStatus(mary), UserStatus.mustSetPassword);
        final entry = (await env.auditFor('user.create')).last;
        expect(entry.userId, owner.id);
        expect(json(entry.afterJson)['password_hash'], '[redacted]');

        final result = await login().login('mary', 'temp-pass-1');
        expect(result.outcome, LoginOutcome.mustChangePassword);
      },
    );

    test('a taken username (any case) and bad fields are refused', () async {
      await addMary();
      await expectLater(
        staff.addReceptionist(
          owner,
          const NewReceptionist(
            fullName: 'Another Mary',
            username: 'MARY',
            temporaryPassword: 'temp-pass-2',
          ),
        ),
        throwsA(
          isA<InvalidReceptionist>().having((e) => e.errors, 'errors', {
            ReceptionistField.username: 'That username is taken.',
          }),
        ),
      );
      await expectLater(
        staff.addReceptionist(
          owner,
          const NewReceptionist(
            fullName: '',
            username: 'ok',
            temporaryPassword: 'x',
          ),
        ),
        throwsA(isA<InvalidReceptionist>()),
      );
    });

    test('lists the owner first, active users by name, disabled last; shows '
        'an open shift', () async {
      final mary = await addMary();
      final james = await staff.addReceptionist(
        owner,
        const NewReceptionist(
          fullName: 'Aaron James',
          username: 'james',
          temporaryPassword: 'temp-pass-1',
        ),
      );
      await staff.disableUser(owner, james.id);
      await ShiftRepository(
        env.db,
        env.audit,
      ).openShift(user: mary, openingFloat: 500);

      final list = await staff.users();
      expect(
        [for (final u in list) u.account.username],
        ['owner', 'mary', 'james'],
      );
      expect(list[1].shiftOpenSince, env.clock.now());
      expect(list[0].shiftOpenSince, isNull);
    });

    test('reset password sets a temporary one to change at sign-in', () async {
      final mary = await addMary();
      await env.users.changePassword(mary.id, 'marys-own-pass');
      expect((await reload(mary.id)).mustChangePassword, isFalse);

      await staff.resetPassword(owner, mary.id, 'new-temp-pass');
      expect((await reload(mary.id)).mustChangePassword, isTrue);
      expect(await env.auditFor('user.reset_password'), hasLength(1));
      expect(
        (await login().login('mary', 'new-temp-pass')).outcome,
        LoginOutcome.mustChangePassword,
      );
      expect(
        (await login().login('mary', 'marys-own-pass')).outcome,
        LoginOutcome.invalidCredentials,
      );
      await expectLater(
        staff.resetPassword(owner, mary.id, 'short'),
        throwsA(isA<StaffRuleViolation>()),
      );
    });

    test('disable stops sign-in; enable restores it and keeps '
        'must_change_password', () async {
      final mary = await addMary();
      await staff.disableUser(owner, mary.id);
      expect(userStatus(await reload(mary.id)), UserStatus.disabled);
      expect(
        (await login().login('mary', 'temp-pass-1')).outcome,
        LoginOutcome.disabled,
      );

      await staff.enableUser(owner, mary.id);
      final back = await reload(mary.id);
      expect(back.isActive, isTrue);
      expect(back.mustChangePassword, isTrue);
      expect(await env.auditFor('user.disable'), hasLength(1));
      expect(await env.auditFor('user.enable'), hasLength(1));
    });

    test('disabling a user with an open shift is allowed', () async {
      final mary = await addMary();
      await ShiftRepository(
        env.db,
        env.audit,
      ).openShift(user: mary, openingFloat: 500);
      await staff.disableUser(owner, mary.id);
      expect((await reload(mary.id)).isActive, isFalse);
    });

    test('the owner cannot disable or reset their own account', () async {
      for (final attempt in [
        () => staff.disableUser(owner, owner.id),
        () => staff.resetPassword(owner, owner.id, 'new-temp-pass'),
      ]) {
        await expectLater(
          attempt(),
          throwsA(
            isA<StaffRuleViolation>().having(
              (e) => e.message,
              'message',
              "You can't change your own account here.",
            ),
          ),
        );
      }
      expect((await reload(owner.id)).isActive, isTrue);
    });

    test('a receptionist cannot manage users', () async {
      final mary = await addMary();
      final desk = await env.addReceptionist('desk');
      for (final attempt in [
        () => staff.disableUser(desk, mary.id),
        () => staff.resetPassword(desk, mary.id, 'new-temp-pass'),
        () => staff.addReceptionist(
          desk,
          const NewReceptionist(
            fullName: 'X Y',
            username: 'xy',
            temporaryPassword: 'temp-pass-1',
          ),
        ),
      ]) {
        await expectLater(
          attempt(),
          throwsA(
            isA<NotPermitted>().having(
              (e) => e.permission,
              'permission',
              Permission.manageUsers,
            ),
          ),
        );
      }
    });
  });

  group('housekeepers', () {
    test('added with a normalized phone, listed active first', () async {
      final rose = await staff.addHousekeeper(
        owner,
        name: ' Rose Akinyi ',
        phone: '+254 722 123 310',
      );
      expect((rose.fullName, rose.phone), ('Rose Akinyi', '0722123310'));
      final john = await staff.addHousekeeper(
        owner,
        name: 'John Mutua',
        phone: '',
      );
      expect(john.phone, isNull);
      await staff.deactivateHousekeeper(owner, rose.id);

      final list = await staff.housekeepers();
      expect(
        [for (final h in list) (h.fullName, h.isActive)],
        [('John Mutua', true), ('Rose Akinyi', false)],
      );
      final created = await env.auditFor('housekeeper.create');
      expect(json(created.first.afterJson)['phone'], '0722•••310');
    });

    test('edit, deactivate and reactivate are each audited', () async {
      final rose = await staff.addHousekeeper(owner, name: 'Rose', phone: '');
      expect(
        await staff.updateHousekeeper(
          owner,
          rose.id,
          name: 'Rose Akinyi',
          phone: '0110 234 567',
        ),
        isTrue,
      );
      expect(
        await staff.updateHousekeeper(
          owner,
          rose.id,
          name: 'Rose Akinyi',
          phone: '0110234567',
        ),
        isFalse,
      );
      await staff.deactivateHousekeeper(owner, rose.id);
      await staff.reactivateHousekeeper(owner, rose.id);
      final h = (await staff.housekeepers()).single;
      expect(
        (h.fullName, h.phone, h.isActive),
        ('Rose Akinyi', '0110234567', true),
      );
      for (final action in [
        'housekeeper.update',
        'housekeeper.deactivate',
        'housekeeper.reactivate',
      ]) {
        expect(await env.auditFor(action), hasLength(1), reason: action);
      }
    });

    test('a bad phone or blank name is refused', () async {
      await expectLater(
        staff.addHousekeeper(owner, name: '', phone: '0822123310'),
        throwsA(
          isA<InvalidHousekeeper>().having(
            (e) => e.errors.keys.toSet(),
            'fields',
            {HousekeeperField.name, HousekeeperField.phone},
          ),
        ),
      );
    });

    test('a receptionist cannot manage housekeepers', () async {
      final desk = await env.addReceptionist('desk');
      await expectLater(
        staff.addHousekeeper(desk, name: 'Rose', phone: ''),
        throwsA(
          isA<NotPermitted>().having(
            (e) => e.permission,
            'permission',
            Permission.manageHousekeepers,
          ),
        ),
      );
    });
  });
}
