import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/schema_check.dart';
import 'package:lodging_pos/features/backup/data/backup_service.dart';
import 'package:lodging_pos/features/backup/presentation/backup_providers.dart';

import '../../../helpers/fixtures.dart';

/// The scheduler with real time and real files (no widgets, so no fake
/// async in the way of file I/O).
void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount desk;
  late Directory temp;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 20, 7, 2));
    supervisor = await env.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('desk');
    temp = Directory.systemTemp.createTempSync('lodging_backup_ui');
    env.backupFolder = temp.path;
  });
  tearDown(() async {
    await env.close();
    temp.deleteSync(recursive: true);
  });

  ProviderContainer start({Duration? interval, SchemaDrift? drift}) {
    env.backupCheck = interval;
    final container = ProviderContainer(
      overrides: [
        ...env.overrides,
        if (drift != null) schemaDriftProvider.overrideWith((_) async => drift),
      ],
    );
    addTearDown(container.dispose);
    container.listen(backupsProvider, (_, _) {});
    return container;
  }

  /// Finished backups (not `.partial` copies still being written).
  List<String> backups() => [
    for (final f in temp.listSync())
      if (f.uri.pathSegments.last.endsWith('.sqlite')) f.uri.pathSegments.last,
  ]..sort();

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue, reason: 'timed out');
  }

  test('once the database check passes, today’s backup is taken; then '
      'nothing more that day', () async {
    final app = start();
    await until(() => app.read(backupsProvider).newest != null);
    expect(backups(), ['lodging_pos-2026-10-20-0702.sqlite']);

    env.clock.set(nairobiInstant(2026, 10, 20, 23, 59));
    await app.read(backupsProvider.notifier).checkNow();
    expect(backups(), hasLength(1));
    final status = app.read(backupsProvider);
    expect(
      (status.enabled, status.running, status.lastFailure),
      (true, false, null),
    );
  });

  test('the hourly check takes the next day’s backup on a desk that stays '
      'on', () async {
    final app = start(interval: const Duration(milliseconds: 20));
    await until(() => backups().length == 1);
    env.clock.set(nairobiInstant(2026, 10, 21, 0, 5)); // after midnight
    const next = 'lodging_pos-2026-10-21-0005.sqlite';
    await until(() => app.read(backupsProvider).newest?.name == next);
    expect(backups(), hasLength(2));
    expect(backups().last, next);
  });

  test('a file that fails the database check is never backed up', () async {
    final app = start(drift: const SchemaDrift(['Changed: table stays']));
    await app.read(schemaDriftProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(backups(), isEmpty);
    expect(app.read(backupsProvider).newest, isNull);
  });

  test('after a shift close, another backup in the background, by that '
      'user', () async {
    final app = start();
    await until(() => backups().length == 1);
    env.clock.set(nairobiInstant(2026, 10, 20, 18, 30));
    app.read(backupsProvider.notifier).afterShiftClose(desk);
    await until(() => backups().length == 2);
    final audit = await env.auditFor('backup.create');
    final afterClose = audit.singleWhere(
      (a) => a.afterJson.contains('"reason":"shift_close"'),
    );
    expect(afterClose.userId, desk.id);
    expect(afterClose.entityId, 'lodging_pos-2026-10-20-1830.sqlite');
  });

  test(
    'Back up now: the supervisor only; one backup at a time, a second request '
    'waits and takes its own',
    () async {
      final app = start();
      await until(() => backups().length == 1);
      final notifier = app.read(backupsProvider.notifier);
      expect(() => notifier.backUpNow(desk), throwsA(isA<NotPermitted>()));

      env.clock.set(nairobiInstant(2026, 10, 20, 9));
      final first = notifier.backUpNow(supervisor);
      final second = notifier.backUpNow(supervisor);
      await Future.wait([first, second]);
      // Same minute, same name: the later copy replaced the first.
      expect(backups(), hasLength(2));
      expect(await env.auditFor('backup.create'), hasLength(3));
      expect(app.read(backupsProvider).running, isFalse);
    },
  );

  test('a failure shows as overdue until a backup succeeds', () async {
    // Today's backup can't be written: its partial file is a folder.
    Directory(
      '${temp.path}${Platform.pathSeparator}'
      'lodging_pos-2026-10-20-0702.sqlite.partial',
    ).createSync();
    final app = start();
    await until(() => app.read(backupsProvider).lastFailure != null);
    expect(app.read(backupsProvider).overdueAt(env.clock.now()), isTrue);

    env.clock.set(nairobiInstant(2026, 10, 20, 7, 3));
    await app.read(backupsProvider.notifier).backUpNow(supervisor);
    final status = app.read(backupsProvider);
    expect(status.lastFailure, isNull);
    expect(status.overdueAt(env.clock.now()), isFalse);
  });

  test('the second folder: set, used, a missing one only noted', () async {
    final usb = Directory('${temp.path}-usb')..createSync();
    addTearDown(() => usb.deleteSync(recursive: true));
    final app = start();
    await until(() => backups().length == 1);
    final notifier = app.read(backupsProvider.notifier);

    await notifier.setSecondFolder(supervisor, usb.path);
    expect(app.read(backupsProvider).secondFolder, usb.path);
    env.clock.set(nairobiInstant(2026, 10, 20, 9));
    await notifier.backUpNow(supervisor);
    expect(app.read(backupsProvider).second, isA<SecondCopied>());

    await notifier.setSecondFolder(supervisor, '${usb.path}-unplugged');
    env.clock.set(nairobiInstant(2026, 10, 20, 9, 1));
    await notifier.backUpNow(supervisor);
    final status = app.read(backupsProvider);
    expect(status.second, isA<SecondSkipped>());
    expect(status.overdueAt(env.clock.now()), isFalse);

    await expectLater(
      notifier.setSecondFolder(desk, null),
      throwsA(isA<NotPermitted>()),
    );
  });

  test('no folder (web, the phone): nothing runs', () async {
    env.backupFolder = null;
    final app = start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(app.read(backupsProvider).enabled, isFalse);
    expect(app.read(backupsProvider).overdueAt(env.clock.now()), isFalse);
    app.read(backupsProvider.notifier).afterShiftClose(desk);
    expect(backups(), isEmpty);
  });
}
