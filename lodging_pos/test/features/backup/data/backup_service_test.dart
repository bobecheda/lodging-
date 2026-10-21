import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/audit/audit_writer.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/schema_check.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/settings/settings_repository.dart';
import 'package:lodging_pos/features/backup/data/backup_service.dart';
import 'package:lodging_pos/features/backup/domain/backup.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount desk;
  late Directory temp;
  late String folder;
  late BackupService backups;

  BackupService serviceFor(AppDatabase db, AuditWriter audit, Clock clock) =>
      BackupService(db, audit, clock, SettingsRepository(db), folder: folder);

  // Restoring opens a backup as a second AppDatabase on purpose.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 20, 7, 2)); // Tue 07:02
    supervisor = await env.users.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('desk');
    temp = Directory.systemTemp.createTempSync('lodging_backup_test');
    folder = '${temp.path}${Platform.pathSeparator}backups';
    backups = serviceFor(env.db, env.audit, env.clock);
  });
  tearDown(() async {
    await env.close();
    temp.deleteSync(recursive: true);
  });

  String inFolder(String name, [String? dir]) =>
      '${dir ?? folder}${Platform.pathSeparator}$name';

  List<String> namesIn(String dir) =>
      [for (final f in Directory(dir).listSync()) f.uri.pathSegments.last]
        ..sort();

  Future<void> letABed() async {
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    await env.checkIn(room.beds.single.id, by: desk, nights: 2);
  }

  /// Opens a backup the way a restore would: as the app's database.
  AppDatabase openCopy(String path) =>
      AppDatabase(NativeDatabase(File(path)), clock: env.clock);

  test('a checked copy named for Nairobi time, audited, that restores to '
      'the same data and schema', () async {
    await letABed();
    final done = await backups.backUp(reason: BackupReason.daily);

    expect(done.file.name, 'lodging_pos-2026-10-20-0702.sqlite');
    expect(done.second, isNull);
    expect(namesIn(folder), [done.file.name]); // no .partial left
    expect(done.file.sizeBytes, File(inFolder(done.file.name)).lengthSync());
    expect((await backups.newest())?.name, done.file.name);

    final audit = (await env.auditFor('backup.create')).single;
    expect(audit.userId, isNull); // automatic
    expect(audit.afterJson, contains('"reason":"daily"'));
    expect(audit.afterJson, contains('"second_copy":"none"'));

    // Restore round-trip: the copy opens as the app's database, matches a
    // fresh schema, and holds the same rows.
    final copy = openCopy(inFolder(done.file.name));
    addTearDown(copy.close);
    final fresh = AppDatabase(NativeDatabase.memory(), clock: env.clock);
    addTearDown(fresh.close);
    expect(await schemaDifferences(copy, fresh), isEmpty);
    Future<List<int>> counts(AppDatabase db) async => [
      for (final TableInfo t in [
        db.stays,
        db.payments,
        db.stayCharges,
        db.users,
      ])
        await db.select(t).get().then((rows) => rows.length),
    ];
    expect(await counts(copy), await counts(env.db));
    expect(await counts(copy), [1, 1, 1, 2]);
    final receipt = await copy.select(copy.receiptCounter).getSingle();
    expect(receipt.nextNumber, 2);
    // Everything audited before the backup is in it.
    final liveAudit = await env.db.select(env.db.auditLog).get();
    final copyAudit = await copy.select(copy.auditLog).get();
    expect(copyAudit.length, liveAudit.length - 1); // minus backup.create
  });

  test('a file database in WAL mode: writes not yet checkpointed are in the '
      'copy, and backing up while the desk writes is safe', () async {
    final dbFile = File('${temp.path}${Platform.pathSeparator}live.sqlite');
    final clock = FixedClock(nairobiInstant(2026, 10, 20, 7, 2));
    final db = AppDatabase(NativeDatabase(dbFile), clock: clock);
    addTearDown(db.close);
    final audit = AuditWriter(db, clock);
    final mode = await db.customSelect('PRAGMA journal_mode').getSingle();
    expect(mode.data.values.first, 'wal');

    Future<void> write(int i) => audit.writeWithAudit(
      action: 'category.create',
      userId: null,
      body: (w) => w.insert(
        db.bedCategories,
        BedCategoriesCompanion.insert(
          name: 'Cat $i',
          pricePerNight: 100 + i,
          sortOrder: 10 + i,
        ),
      ),
    );
    await write(0);
    final service = serviceFor(db, audit, clock);
    // The backup and more writes at the same time.
    final results = await Future.wait([
      service.backUp(reason: BackupReason.daily),
      for (var i = 1; i <= 5; i++) write(i),
    ]);
    final done = results.first as BackupDone;

    final copy = AppDatabase(
      NativeDatabase(File(inFolder(done.file.name))),
      clock: clock,
    );
    addTearDown(copy.close);
    final names = [
      for (final c in await copy.select(copy.bedCategories).get()) c.name,
    ];
    expect(names, contains('Cat 0')); // written before, still in the WAL
    // A consistent moment: each category came with its audit row.
    final created = await (copy.select(
      copy.auditLog,
    )..where((a) => a.action.equals('category.create'))).get();
    expect(created.length, names.where((n) => n.startsWith('Cat')).length);
    final live = await db.select(db.bedCategories).get();
    expect(live.where((c) => c.name.startsWith('Cat')), hasLength(6));
  });

  test('a failed copy never replaces a good one and leaves no partial '
      'file; the failure is audited', () async {
    final good = await backups.backUp(reason: BackupReason.daily);
    final goodSize = File(inFolder(good.file.name)).lengthSync();
    // Same minute: the next copy would replace it, but can't be written.
    Directory(inFolder('${good.file.name}.partial')).createSync();

    await expectLater(
      backups.backUp(reason: BackupReason.shiftClose, by: desk),
      throwsA(
        isA<BackupFailed>().having(
          (e) => e.message,
          'message',
          'The backup file couldn’t be written in the folder.',
        ),
      ),
    );
    expect(File(inFolder(good.file.name)).lengthSync(), goodSize);
    expect(File(inFolder('${good.file.name}.partial')).existsSync(), isFalse);
    final failed = (await env.auditFor('backup.failed')).single;
    expect(failed.userId, desk.id);
    expect(failed.afterJson, contains('"reason":"shift_close"'));
  });

  test('an unreachable folder fails with the reason', () async {
    File(folder).writeAsStringSync('not a folder');
    await expectLater(
      backups.backUp(reason: BackupReason.daily),
      throwsA(isA<BackupFailed>()),
    );
    expect(await env.auditFor('backup.failed'), hasLength(1));
  });

  test('old backups are pruned; other files are left alone', () async {
    Directory(folder).createSync();
    final old = [
      backupFileName(nairobiInstant(2026, 9, 1, 7)), // older than 30 days
      backupFileName(nairobiInstant(2026, 10, 10, 7)), // not the day's last
      backupFileName(nairobiInstant(2026, 10, 10, 19)),
      backupFileName(nairobiInstant(2026, 10, 19, 7)), // yesterday: all kept
      backupFileName(nairobiInstant(2026, 10, 19, 19)),
    ];
    for (final name in [...old, 'notes.txt']) {
      File(inFolder(name)).writeAsStringSync('x');
    }

    final done = await backups.backUp(reason: BackupReason.daily);
    expect(namesIn(folder), [
      'lodging_pos-2026-10-10-1900.sqlite',
      'lodging_pos-2026-10-19-0700.sqlite',
      'lodging_pos-2026-10-19-1900.sqlite',
      done.file.name,
      'notes.txt',
    ]);
  });

  group('second folder', () {
    late String second;
    setUp(() => second = '${temp.path}${Platform.pathSeparator}usb');

    test('each backup is copied there too, and pruned the same way', () async {
      Directory(second).createSync();
      File(inFolder(backupFileName(nairobiInstant(2026, 9, 1, 7)), second))
          .writeAsStringSync('x');
      await backups.setSecondFolder(supervisor, second);
      expect(await backups.secondFolder(), second);

      final done = await backups.backUp(reason: BackupReason.daily);
      expect(done.second, isA<SecondCopied>());
      expect(namesIn(second), [done.file.name]);
      expect(
        File(inFolder(done.file.name, second)).lengthSync(),
        done.file.sizeBytes,
      );
      expect(
        (await env.auditFor('backup.create')).single.afterJson,
        contains('"second_copy":"copied"'),
      );
      expect([
        for (final a in await env.auditFor('settings.update'))
          if (a.entityId == 'backup_second_folder') a,
      ], hasLength(1));
    });

    test('a missing folder (USB drive unplugged) is skipped; the main '
        'backup still counts', () async {
      await backups.setSecondFolder(supervisor, second); // never created
      final done = await backups.backUp(reason: BackupReason.daily);
      expect(done.second, isA<SecondSkipped>());
      expect(File(inFolder(done.file.name)).existsSync(), isTrue);
      expect(await env.auditFor('backup.failed'), isEmpty);
      expect(
        (await env.auditFor('backup.create')).single.afterJson,
        contains('"second_copy":"skipped"'),
      );
    });

    test('a copy that fails there is reported, the main backup kept', () async {
      Directory(second).createSync();
      await backups.setSecondFolder(supervisor, second);
      final name = backupFileName(env.clock.now());
      Directory(inFolder('$name.partial', second)).createSync();

      final done = await backups.backUp(reason: BackupReason.daily);
      expect(done.second, isA<SecondFailed>());
      expect(File(inFolder(name)).existsSync(), isTrue);
    });

    test('removing it clears the setting', () async {
      await backups.setSecondFolder(supervisor, second);
      await backups.setSecondFolder(supervisor, null);
      expect(await backups.secondFolder(), isNull);
      final done = await backups.backUp(reason: BackupReason.daily);
      expect(done.second, isNull);
    });
  });

  test('Back up now and the folders need manageBackups; the daily one runs '
      'for anyone or no one', () async {
    await expectLater(
      backups.backUp(reason: BackupReason.manual, by: desk),
      throwsA(isA<NotPermitted>()),
    );
    await expectLater(
      backups.setSecondFolder(desk, temp.path),
      throwsA(isA<NotPermitted>()),
    );
    await backups.backUp(reason: BackupReason.manual, by: supervisor);
    env.clock.set(nairobiInstant(2026, 10, 21, 7));
    await backups.backUp(reason: BackupReason.daily, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 22, 7));
    await backups.backUp(reason: BackupReason.daily);
    expect(await env.auditFor('backup.create'), hasLength(3));
  });
}
