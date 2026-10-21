import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/features/auth/data/user_repository.dart';
import 'package:lodging_pos/features/auth/domain/setup.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  group('first-run setup (fresh install): the owner', () {
    test('a fresh database has no users and no owner', () async {
      expect(await env.users.hasAnyUser(), isFalse);
      expect(await env.users.setupState(), SetupState.fresh);
    });

    test('creates the owner with a normalized username and hashed password; '
        'setup is then done', () async {
      final owner = await env.users.createFirstOwner(testOwner);
      expect(owner.username, 'owner');
      expect(owner.fullName, 'Amina Owner');
      expect(owner.role, Role.owner);
      expect(owner.mustChangePassword, isFalse);
      expect(await env.users.setupState(), SetupState.ready);

      final stored = (await env.users.findByUsername('owner'))!;
      expect(stored.passwordHash, isNot('owner-pass'));
      expect(
        await env.hasher.verify('owner-pass', stored.passwordHash),
        isTrue,
      );
    });

    test('sets the lodging name; user.create (role owner) and '
        'settings.update as one operation by the owner', () async {
      final owner = await env.users.createFirstOwner(testOwner);
      final row = await (env.db.select(
        env.db.settings,
      )..where((s) => s.key.equals('lodging_name'))).getSingle();
      expect((row.value, row.updatedBy), ('Sunrise Lodge', owner.id));

      final entries = await env.db.select(env.db.auditLog).get();
      expect(
        [for (final e in entries) (e.action, e.entity)],
        [('user.create', 'users'), ('settings.update', 'settings')],
      );
      expect(entries.map((e) => e.operationId).toSet(), hasLength(1));
      expect(entries.map((e) => e.userId).toSet(), {owner.id});
      final after = jsonDecode(entries.first.afterJson) as Map<String, Object?>;
      expect(after['role'], 'owner');
      expect(after['password_hash'], '[redacted]');
    });

    test('cannot run once any user exists', () async {
      await env.users.createFirstOwner(testOwner);
      await expectLater(
        env.users.createFirstOwner(testOwner.copyWith(username: 'second')),
        throwsA(isA<SetupAlreadyDone>()),
      );
      expect(await env.db.select(env.db.users).get(), hasLength(1));
      expect(await env.auditFor('user.create'), hasLength(1));
    });

    test('rejects an invalid form without writing', () async {
      await expectLater(
        env.users.createFirstOwner(testOwner.copyWith(confirmPassword: 'no')),
        throwsArgumentError,
      );
      expect(await env.users.hasAnyUser(), isFalse);
    });
  });

  group('a database from before the owner role', () {
    /// A supervisor and a receptionist, no owner (as after the v6 upgrade).
    Future<void> withoutOwner() async {
      await env.addReceptionist('desk');
      await env.audit.writeWithAudit(
        action: 'user.create',
        userId: null,
        body: (w) => w.insert(
          env.db.users,
          UsersCompanion.insert(
            fullName: 'Grace Supervisor',
            username: 'supervisor',
            passwordHash: 'x',
            role: Role.supervisor.name,
            mustChangePassword: false,
          ),
        ),
      );
    }

    test('needs the owner; creating it (no lodging name asked) makes setup '
        'ready, once only', () async {
      await withoutOwner();
      expect(await env.users.setupState(), SetupState.needsOwner);

      final owner = await env.users.createMissingOwner(
        testOwner.copyWith(lodgingName: ''),
      );
      expect(owner.role, Role.owner);
      expect(await env.users.setupState(), SetupState.ready);
      expect(await env.auditFor('settings.update'), isEmpty);
      final created = await env.auditFor('user.create');
      expect(
        (jsonDecode(created.last.afterJson) as Map<String, Object?>)['role'],
        'owner',
      );

      await expectLater(
        env.users.createMissingOwner(
          testOwner.copyWith(username: 'second', lodgingName: ''),
        ),
        throwsA(isA<SetupAlreadyDone>()),
      );
    });

    test('a username already in use is refused', () async {
      await withoutOwner();
      await expectLater(
        env.users.createMissingOwner(
          testOwner.copyWith(username: 'Supervisor', lodgingName: ''),
        ),
        throwsA(isA<UsernameTaken>()),
      );
      expect(await env.users.hasOwner(), isFalse);
    });
  });

  group('the test fixture', () {
    test(
      'sets up the owner by the real first run, then the supervisor',
      () async {
        final supervisor = await env.createFirstSupervisor(testSetup);
        expect(
          (supervisor.username, supervisor.role),
          ('supervisor', Role.supervisor),
        );
        expect(env.owner?.role, Role.owner);
        expect(await env.users.setupState(), SetupState.ready);
      },
    );
  });

  group('findByUsername', () {
    test('ignores case and surrounding spaces', () async {
      await env.createFirstSupervisor(testSetup);
      expect(
        (await env.users.findByUsername('  SUPERVISOR '))?.account.username,
        'supervisor',
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
