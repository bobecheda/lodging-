import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/owner_password.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/cloud_writes.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_store.dart';
import 'package:lodging_pos/features/auth/data/login_service.dart';
import 'package:lodging_pos/features/auth/data/owner_password_service.dart';
import 'package:lodging_pos/features/auth/domain/login.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/fixtures.dart';

/// A new password, made up.
const phonePassword = 'set-on-phone-1';
const deskPassword = 'set-at-desk-1';

/// The owner's password on the desk once it is also a cloud sign-in
/// (owner-app-3): the desk follows a change made on the phone, and its own
/// change goes to the cloud first.
void main() {
  late TestEnv env;
  late UserAccount owner;
  late FakeCloud cloud;
  late SyncEngine engine;
  late LoginService login;
  late OwnerPasswordService passwords;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 25, 9));
    await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    cloud = FakeCloud(serverNow: () => env.clock.now());
    engine = SyncEngine(
      db: env.db,
      audit: env.audit,
      cloud: cloud,
      secrets: env.deskSecrets,
      clock: env.clock,
    );
    await engine.start();
    await engine.connect(
      owner: owner,
      installCode: 'ABCD-EFGH-JKLM',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );
    login = LoginService(env.users, env.hasher, env.audit, cloud: engine);
    passwords = OwnerPasswordService(env.users, env.hasher, cloud: engine);
  });
  tearDown(() async {
    await engine.dispose();
    await env.close();
  });

  Future<String?> stored(String key) => SyncStore(env.db).get(key);

  Future<LoginOutcome> signIn(String password) async =>
      (await login.login('owner', password)).outcome;

  test('changed on the phone: after the pull the desk refuses its own copy; '
      'the new password, online, is taken and kept', () async {
    env.clock.advance(const Duration(minutes: 5));
    cloud.phoneChangesPassword(phonePassword);
    // Before the pull the desk can't know: its copy still works.
    expect(await signIn(testOwner.password), LoginOutcome.success);

    await engine.pullNow();
    expect(await engine.isOwnerPasswordBehind(), isTrue);
    expect(
      await signIn(testOwner.password),
      LoginOutcome.passwordChangedElsewhere,
    );
    cloud.offline = true;
    expect(await signIn(phonePassword), LoginOutcome.passwordChangedElsewhere);
    expect(
      (await env.auditFor('user.login_failed')).last.afterJson,
      contains('passwordChangedElsewhere'),
    );

    cloud.offline = false;
    expect(await signIn(phonePassword), LoginOutcome.success);
    expect(await env.auditFor('user.password_from_cloud'), hasLength(1));
    expect(await engine.isOwnerPasswordBehind(), isFalse);
    expect(
      await stored(SyncStore.passwordDeskAt),
      await stored(SyncStore.passwordCloudAt),
    );
    // The desk's copy is the new one now, offline too; the old is gone.
    cloud.offline = true;
    expect(await signIn(phonePassword), LoginOutcome.success);
    expect(await signIn(testOwner.password), LoginOutcome.invalidCredentials);
  });

  test('the phone ends the owner’s other sessions: the desk’s sync goes '
      'on; only the owner’s cloud sign-in on the desk ends', () async {
    final supervisor = (await env.users.findByUsername('supervisor'))!.account;
    cloud.phoneChangesPassword(phonePassword);
    await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '9',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    await engine.syncNow();
    expect(await SyncStore(env.db).pendingCount(), 0);
    expect(cloud.count('rooms'), greaterThan(0));
    expect(cloud.ownerSignedIn, isFalse);
    await expectLater(
      engine.changeOwnerPassword(current: testOwner.password, next: 'x' * 8),
      throwsA(isA<OwnerPasswordRefused>()),
    );
  });

  test('changed at the desk offline: refused with the message; nothing '
      'changes here or in the cloud', () async {
    cloud.offline = true;
    await expectLater(
      passwords.change(owner, current: testOwner.password, next: deskPassword),
      throwsA(
        isA<PasswordChangeRefused>().having(
          (e) => e.message,
          'message',
          changingPasswordNeedsInternet,
        ),
      ),
    );
    expect(cloud.ownerPassword, testOwner.password);
    expect(cloud.count('owner_password_changes'), 0);
    expect(await signIn(testOwner.password), LoginOutcome.success);
    expect(await env.auditFor('user.change_password'), isEmpty);
  });

  test('changed at the desk online: recorded, set in the cloud, then here; '
      'the desk’s own change pulled back changes nothing', () async {
    await passwords.change(
      owner,
      current: testOwner.password,
      next: deskPassword,
    );
    expect(cloud.ownerPassword, deskPassword);
    expect(cloud.count('owner_password_changes'), 1);
    expect(await env.auditFor('user.change_password'), hasLength(1));
    await engine.pullNow();
    expect(await engine.isOwnerPasswordBehind(), isFalse);
    cloud.offline = true;
    expect(await signIn(deskPassword), LoginOutcome.success);
  });

  test('wrong current password, too short, the same: refused before the '
      'cloud', () async {
    for (final (current, next, message) in [
      ('not-it-at-all', deskPassword, 'That isn’t your current password.'),
      (testOwner.password, 'short', 'At least 8 characters'),
      (
        testOwner.password,
        testOwner.password,
        'Choose a password different from the current one.',
      ),
    ]) {
      await expectLater(
        passwords.change(owner, current: current, next: next),
        throwsA(
          isA<PasswordChangeRefused>().having((e) => e.message, 'm', message),
        ),
      );
    }
    expect(cloud.count('owner_password_changes'), 0);
  });

  test(
    'recorded, but setting it fails: the error, and later one online '
    'sign-in with the unchanged password brings the desk up to date',
    () async {
      cloud.failPasswordUpdate = true;
      await expectLater(
        passwords.change(
          owner,
          current: testOwner.password,
          next: deskPassword,
        ),
        throwsA(
          isA<PasswordChangeRefused>().having(
            (e) => e.message,
            'message',
            startsWith('The new password wasn’t saved in the cloud'),
          ),
        ),
      );
      expect(cloud.count('owner_password_changes'), 1);
      expect(cloud.ownerPassword, testOwner.password);
      expect(await env.auditFor('user.change_password'), isEmpty);

      await engine.pullNow();
      expect(await engine.isOwnerPasswordBehind(), isTrue);
      expect(await signIn(testOwner.password), LoginOutcome.success);
      expect(await env.auditFor('user.password_from_cloud'), hasLength(1));
      expect(await engine.isOwnerPasswordBehind(), isFalse);
      expect(
        await stored(SyncStore.passwordDeskAt),
        await stored(SyncStore.passwordCloudAt),
      );
    },
  );
}
