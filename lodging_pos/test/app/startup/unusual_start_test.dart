import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/startup/unusual_start.dart';
import 'package:lodging_pos/core/database/desk_meta.dart';
import 'package:lodging_pos/core/database/desk_startup.dart';

import '../../helpers/fixtures.dart';

/// Starting the desk from a USB drive or another folder (story/desk-db-
/// guards): a warning the supervisor or owner may accept, audited; never a
/// receptionist.
void main() {
  late TestEnv env;
  late UnusualStartService service;

  setUp(() async {
    env = TestEnv();
    await env.createFirstSupervisor(testSetup);
    service = UnusualStartService(env.db, env.audit, env.users, env.hasher);
  });
  tearDown(() => env.close());

  const usb = UnusualLocation(
    path: r'D:\Release',
    removable: true,
    recorded: r'C:\UB40\Desk',
  );
  const moved = UnusualLocation(
    path: r'C:\UB40\Desk-1.1',
    removable: false,
    recorded: r'C:\UB40\Desk',
  );

  test(
    'the supervisor accepts: audited with the path and the reason',
    () async {
      await service.accept(
        usb,
        username: 'supervisor',
        password: 'super-pass',
        makeInstallFolder: false,
      );
      final audit = (await env.auditFor('desk.unusual_start')).single;
      expect(audit.afterJson, contains(r'D:\\Release'));
      expect(audit.afterJson, contains('"removable":true'));
      expect(await installPath(env.db), isNull);
    },
  );

  test(
    'the owner accepts a new folder and makes it the install folder',
    () async {
      await service.accept(
        moved,
        username: 'owner',
        password: 'owner-pass',
        makeInstallFolder: true,
      );
      expect(await installPath(env.db), r'C:\UB40\Desk-1.1');
    },
  );

  test('a removable drive never becomes the install folder', () async {
    await service.accept(
      usb,
      username: 'owner',
      password: 'owner-pass',
      makeInstallFolder: true,
    );
    expect(await installPath(env.db), isNull);
  });

  test(
    'a receptionist can’t; a wrong password can’t; nothing audited',
    () async {
      await env.addReceptionist('desk');
      for (final (user, password) in [
        ('desk', 'desk-pass'),
        ('supervisor', 'wrong'),
        ('nobody', 'x'),
      ]) {
        await expectLater(
          service.accept(
            usb,
            username: user,
            password: password,
            makeInstallFolder: false,
          ),
          throwsA(isA<UnusualStartRefused>()),
        );
      }
      expect(await env.auditFor('desk.unusual_start'), isEmpty);
    },
  );
}
