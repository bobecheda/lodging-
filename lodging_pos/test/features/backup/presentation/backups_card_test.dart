import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/backup/domain/backup.dart';
import 'package:lodging_pos/features/backup/presentation/backup_providers.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late Directory temp;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 20, 9)); // Tue 09:00
    await env.createFirstSupervisor(testSetup);
    temp = Directory.systemTemp.createTempSync('lodging_backup_card');
    env.backupFolder = temp.path;
  });
  tearDown(() async {
    await env.close();
    temp.deleteSync(recursive: true);
  });

  String inTemp(String name) => '${temp.path}${Platform.pathSeparator}$name';

  /// Taps [key] without settling: its spinner turns until the backup's
  /// file I/O finishes, which only [settleRealIo] lets happen.
  Future<void> press(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  BackupStatus status(ProviderContainer app) => app.read(backupsProvider);

  Finder richText(String key, String text) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.textContaining(text, findRichText: true),
  );

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  /// Today's backup at start blocked: its partial file is a folder.
  void blockTodaysBackup() =>
      Directory(inTemp('${backupFileName(env.clock.now())}.partial'))
          .createSync();

  testWidgets('today’s backup at start; the card shows it, opens its '
      'folder, and Back up now adds another', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await settleRealIo(tester, () => status(app).newest != null);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'nav.${Routes.adminPrices}');

    expect(richText('backups.last', 'Last backup Today 09:00 · '), findsOne);
    expect(richText('backups.last', ' · checked'), findsOne);
    expect(text(tester, 'backups.folder'), temp.path);
    expect(find.byKey(const ValueKey('shell.backupPill')), findsNothing);

    await tapKey(tester, 'backups.openFolder');
    expect(env.backupShell.opened, [temp.path]);

    env.clock.set(nairobiInstant(2026, 10, 20, 9, 5));
    await press(tester, 'backups.now');
    await settleRealIo(
      tester,
      () => status(app).newest?.name == 'lodging_pos-2026-10-20-0905.sqlite',
    );
    expect(richText('backups.last', 'Today 09:05'), findsOne);
    expect(
      temp.listSync().map((f) => f.uri.pathSegments.last).toList()..sort(),
      [
        'lodging_pos-2026-10-20-0900.sqlite',
        'lodging_pos-2026-10-20-0905.sqlite',
      ],
    );
  });

  testWidgets('a failed backup: a receptionist sees the chip, which leads '
      'nowhere for them', (tester) async {
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 0);
    File(inTemp(backupFileName(nairobiInstant(2026, 10, 18, 7))))
        .writeAsStringSync('x');
    blockTodaysBackup();

    final app = await pumpDeskApp(tester, env);
    await settleRealIo(tester, () => status(app).lastFailure != null);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('shell.backupPill')),
        matching: find.text('Backup failed · last Sun 18 Oct'),
      ),
      findsOne,
    );
    final pill = tester.widget<InkWell>(
      find.byKey(const ValueKey('shell.backupPill')),
    );
    expect(pill.onTap, isNull);
    expect(find.byKey(ValueKey('nav.${Routes.adminPrices}')), findsNothing);
  });

  testWidgets('a failed backup: the supervisor’s chip opens the card with the '
      'reason; Back up now that works clears both', (tester) async {
    blockTodaysBackup();
    final app = await pumpDeskApp(tester, env);
    await settleRealIo(tester, () => status(app).lastFailure != null);
    await signInAs(tester, 'supervisor', 'super-pass');

    expect(find.text('Backup failed · none yet'), findsOne);
    await tapKey(tester, 'shell.backupPill');
    expect(locationOf(app), Routes.adminPrices);
    expect(find.byKey(const ValueKey('backups.failed')), findsOne);
    expect(text(tester, 'backups.last'), 'No backup yet.');

    Directory(inTemp('${backupFileName(env.clock.now())}.partial'))
        .deleteSync();
    await press(tester, 'backups.now');
    await settleRealIo(tester, () => status(app).lastFailure == null);
    expect(find.byKey(const ValueKey('backups.failed')), findsNothing);
    expect(find.byKey(const ValueKey('shell.backupPill')), findsNothing);
  });

  testWidgets('the second folder: chosen, copied to; unplugged, only a '
      'quiet note; removed', (tester) async {
    final usb = Directory('${temp.path}-usb')..createSync();
    addTearDown(() => usb.deleteSync(recursive: true));
    final app = await pumpDeskApp(tester, env);
    await settleRealIo(tester, () => status(app).newest != null);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'nav.${Routes.adminPrices}');
    expect(text(tester, 'backups.second.none'), 'Not set.');

    env.backupShell.pick = usb.path;
    await tapKey(tester, 'backups.second.choose');
    await settleRealIo(tester, () => status(app).secondFolder == usb.path);
    expect(text(tester, 'backups.second.folder'), usb.path);
    expect(find.byKey(const ValueKey('backups.second.privacy')), findsOne);

    env.clock.set(nairobiInstant(2026, 10, 20, 9, 1));
    await press(tester, 'backups.now');
    await settleRealIo(tester, () => status(app).second != null);
    expect(text(tester, 'backups.second.note'), 'Copied with the last backup.');
    expect(
      File(
        '${usb.path}${Platform.pathSeparator}'
        'lodging_pos-2026-10-20-0901.sqlite',
      ).existsSync(),
      isTrue,
    );

    final unplugged = '${usb.path}-gone';
    env.backupShell.pick = unplugged;
    await tapKey(tester, 'backups.second.choose');
    await settleRealIo(tester, () => status(app).secondFolder == unplugged);
    env.clock.set(nairobiInstant(2026, 10, 20, 9, 2));
    await press(tester, 'backups.now');
    await settleRealIo(tester, () => status(app).second != null);
    expect(
      text(tester, 'backups.second.note'),
      'Second copy skipped: USB drive not found. Main backup OK.',
    );
    expect(find.byKey(const ValueKey('shell.backupPill')), findsNothing);

    await tapKey(tester, 'backups.second.remove');
    await settleRealIo(tester, () => status(app).secondFolder == null);
    expect(text(tester, 'backups.second.none'), 'Not set.');
  });

  testWidgets('no backups on this device (web, the phone): no card', (
    tester,
  ) async {
    env.backupFolder = null;
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'nav.${Routes.adminPrices}');
    expect(find.byKey(const ValueKey('backups.card')), findsNothing);
    expect(find.byKey(const ValueKey('shell.backupPill')), findsNothing);
  });
}
