import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/auth/data/user_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  group('first-run setup', () {
    test('a fresh database has no users', () async {
      expect(await env.users.hasAnyUser(), isFalse);
    });

    test(
      'creates the admin with a normalized username and hashed password',
      () async {
        final admin = await env.users.createFirstAdmin(testSetup);
        expect(admin.username, 'owner');
        expect(admin.fullName, 'Grace Owner');
        expect(admin.role, Role.admin);
        expect(admin.mustChangePassword, isFalse);
        expect(await env.users.hasAnyUser(), isTrue);

        final stored = (await env.users.findByUsername('owner'))!;
        expect(stored.passwordHash, isNot('owner-pass'));
        expect(
          await env.hasher.verify('owner-pass', stored.passwordHash),
          isTrue,
        );
      },
    );

    test('sets the lodging name, updated by the new admin', () async {
      final admin = await env.users.createFirstAdmin(testSetup);
      final row = await (env.db.select(
        env.db.settings,
      )..where((s) => s.key.equals('lodging_name'))).getSingle();
      expect(row.value, 'Sunrise Lodge');
      expect(row.updatedBy, admin.id);
    });

    test(
      'audits user.create and settings.update as one operation by the admin',
      () async {
        final admin = await env.users.createFirstAdmin(testSetup);
        final entries = await env.db.select(env.db.auditLog).get();
        expect(
          [for (final e in entries) (e.action, e.entity)],
          [('user.create', 'users'), ('settings.update', 'settings')],
        );
        expect(entries.map((e) => e.operationId).toSet(), hasLength(1));
        expect(entries.map((e) => e.userId).toSet(), {admin.id});
        expect(
          jsonDecode(entries.first.afterJson)['password_hash'],
          '[redacted]',
        );
      },
    );

    test('cannot run once any user exists', () async {
      await env.users.createFirstAdmin(testSetup);
      await expectLater(
        env.users.createFirstAdmin(testSetup.copyWith(username: 'second')),
        throwsA(isA<SetupAlreadyDone>()),
      );
      expect(await env.db.select(env.db.users).get(), hasLength(1));
      expect(await env.auditFor('user.create'), hasLength(1));
    });

    test('rejects an invalid form without writing', () async {
      await expectLater(
        env.users.createFirstAdmin(testSetup.copyWith(confirmPassword: 'nope')),
        throwsArgumentError,
      );
      expect(await env.users.hasAnyUser(), isFalse);
    });
  });

  group('findByUsername', () {
    test('ignores case and surrounding spaces', () async {
      await env.users.createFirstAdmin(testSetup);
      expect(
        (await env.users.findByUsername('  OWNER '))?.account.username,
        'owner',
      );
      expect(await env.users.findByUsername('nobody'), isNull);
    });
  });

  group('changePassword', () {
    test(
      'replaces the hash, clears must_change_password and audits it',
      () async {
        final desk = await env.addReceptionist(
          'desk',
          mustChangePassword: true,
        );
        final updated = await env.users.changePassword(desk.id, 'new-password');
        expect(updated.mustChangePassword, isFalse);

        final stored = (await env.users.findByUsername('desk'))!;
        expect(
          await env.hasher.verify('new-password', stored.passwordHash),
          isTrue,
        );
        expect(
          await env.hasher.verify('desk-pass', stored.passwordHash),
          isFalse,
        );

        final entry = (await env.auditFor('user.change_password')).single;
        expect(entry.userId, desk.id);
        expect(jsonDecode(entry.afterJson)['password_hash'], '[redacted]');
        expect(jsonDecode(entry.afterJson)['must_change_password'], isFalse);
      },
    );

    test('rejects a short password', () async {
      final desk = await env.addReceptionist('desk');
      await expectLater(
        env.users.changePassword(desk.id, 'short'),
        throwsArgumentError,
      );
    });
  });
}
