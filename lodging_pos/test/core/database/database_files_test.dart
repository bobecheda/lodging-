import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/app_version.dart';
import 'package:lodging_pos/core/audit/audit_writer.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/database_files_native.dart';
import 'package:lodging_pos/core/database/desk_meta.dart';
import 'package:lodging_pos/core/database/desk_startup.dart';
import 'package:lodging_pos/core/auth/password_hasher.dart';
import 'package:lodging_pos/features/auth/data/user_repository.dart';

import '../../helpers/fixtures.dart';

/// The one place for live-file work (story/desk-db-guards): reading the
/// file without opening it for writing, the mark, the lock and the debug
/// reset. Real files in temporary folders.
void main() {
  late Directory dir;
  String at(String name) => '${dir.path}${Platform.pathSeparator}$name';

  setUp(() => dir = Directory.systemTemp.createTempSync('desk_files'));
  tearDown(() {
    releaseDataFolderLock();
    dir.deleteSync(recursive: true);
  });

  /// A real database file in [dir], with the owner made by the real first
  /// run (so it has users and audit entries).
  Future<void> makeDatabase({AppBuild? stampedBy, String? installPath}) async {
    final clock = FixedClock(testT0);
    final db = AppDatabase(
      NativeDatabase(File(at(databaseFileName))),
      clock: clock,
    );
    final audit = AuditWriter(db, clock);
    await UserRepository(
      db,
      audit,
      const PasswordHasher.fast(),
    ).createFirstOwner(testOwner);
    if (stampedBy != null) await raiseBuildStamp(db, stampedBy);
    if (installPath != null) await recordInstallPath(db, installPath);
    await db.close();
  }

  group('inspecting the data folder', () {
    test('an empty folder: no file, nothing around it', () async {
      final i = (await inspectDataFolder(dir.path));
      expect(i.live, isNull);
      expect(i.hasBackups, isFalse);
      expect(i.mark, isNull);
    });

    test('no file, but a daily backup, a pre-upgrade copy or a reset '
        'folder: there was one', () async {
      for (final make in <void Function()>[
        () => File(
          at(
            'backups${Platform.pathSeparator}'
            'lodging_pos-2026-11-24-0720.sqlite',
          ),
        )..createSync(recursive: true),
        () => File(at('lodging_pos.sqlite.v10.bak')).createSync(),
        () => Directory(at('reset-20261124-072000')).createSync(),
      ]) {
        for (final e in dir.listSync()) {
          e.deleteSync(recursive: true);
        }
        make();
        expect((await inspectDataFolder(dir.path)).hasBackups, isTrue);
      }
    });

    test('a real file is read without being changed', () async {
      await makeDatabase(
        stampedBy: const AppBuild(version: '1.2.0', build: 4),
        installPath: r'C:\UB40\Desk',
      );
      final before = File(at(databaseFileName)).readAsBytesSync();
      final live = (await inspectDataFolder(dir.path)).live!;
      expect(
        live.figures.schemaVersion,
        AppDatabase(
          NativeDatabase.memory(),
          clock: FixedClock(testT0),
        ).schemaVersion,
      );
      expect(live.figures.stays, 0);
      expect(live.figures.payments, 0);
      expect(live.figures.auditEntries, greaterThan(0));
      expect(live.figures.lastAuditAt, testT0);
      expect(live.figures.lastReceipt, isNull);
      expect(live.stamp, const DeskStamp(version: '1.2.0', build: 4));
      expect(live.installPath, r'C:\UB40\Desk');
      expect(live.everConnected, isFalse);
      expect(live.nextReceiptNumber, 1);
      expect(live.deviceId, isNotNull);
      expect(live.ownerEmail, isNull); // never connected
      expect(File(at(databaseFileName)).readAsBytesSync(), before);
    });

    test('the build stamp only ever goes up', () async {
      await makeDatabase(stampedBy: const AppBuild(version: '1.2.0', build: 4));
      final db = AppDatabase(
        NativeDatabase(File(at(databaseFileName))),
        clock: FixedClock(testT0),
      );
      await raiseBuildStamp(db, const AppBuild(version: '1.0.0', build: 2));
      await db.close();
      expect(
        (await inspectDataFolder(dir.path)).live!.stamp,
        const DeskStamp(version: '1.2.0', build: 4),
      );
    });
  });

  group('the high-water mark', () {
    final mark = HighWaterMark(
      backupName: 'lodging_pos-2026-11-24-0720.sqlite',
      takenAt: testT0,
      figures: DatabaseFigures(
        schemaVersion: 11,
        stays: 30,
        payments: 46,
        auditEntries: 711,
        lastReceipt: 'R-000050',
        lastAuditAt: testT0,
      ),
      build: const DeskStamp(version: '1.0.0', build: 2),
    );

    test('written whole, read back', () async {
      writeMark(dir.path, mark);
      expect(File(at('$markFileName.partial')).existsSync(), isFalse);
      expect(readMark(dir.path)!.figures, mark.figures);
      expect(
        (await inspectDataFolder(dir.path)).mark!.backupName,
        mark.backupName,
      );
    });

    test('an unreadable mark counts as none', () {
      File(at(markFileName)).writeAsStringSync('{not json');
      expect(readMark(dir.path), isNull);
    });
  });

  group('two marks that move with the work (story/desk-db-guards-2)', () {
    late String second;
    setUp(() => second = Directory(at('local')).path);

    DatabaseFigures figures({int payments = 46, String receipt = 'R-000050'}) =>
        DatabaseFigures(
          schemaVersion: 12,
          stays: 30,
          payments: payments,
          auditEntries: 711,
          lastReceipt: receipt,
          lastAuditAt: testT0,
        );
    const build = DeskStamp(version: '1.1.0', build: 3);
    MarkFiles marks() => MarkFiles(dir.path, second, build: build);

    test('raised in both places, each written whole', () async {
      await marks().raise(figures(), at: testT0);
      for (final folder in [dir.path, second]) {
        expect(readMark(folder)!.figures, figures(), reason: folder);
        expect(
          File('$folder${Platform.pathSeparator}$markFileName.partial')
              .existsSync(),
          isFalse,
        );
      }
      final i = await inspectDataFolder(dir.path, secondFolder: second);
      expect(i.mark!.figures, figures());
      expect(i.secondMark!.figures, figures());
    });

    test('never lowered by a raise, and a lost copy comes back from the '
        'other', () async {
      final later = testT0.add(const Duration(minutes: 3));
      await marks().raise(
        figures(payments: 47, receipt: 'R-000051'),
        at: later,
      );
      File('$second${Platform.pathSeparator}$markFileName').deleteSync();
      await marks().raise(
        figures(),
        at: later.add(const Duration(minutes: 1)),
        backupName: 'lodging_pos-2026-11-11-1103.sqlite',
      );
      for (final folder in [dir.path, second]) {
        final m = readMark(folder)!;
        expect(m.figures.payments, 47, reason: folder);
        expect(m.figures.lastReceipt, 'R-000051');
        expect(m.backupName, 'lodging_pos-2026-11-11-1103.sqlite');
      }
    });

    test('the higher copy wins when the data folder came back with an old '
        'mark', () async {
      await marks().raise(
        figures(payments: 47, receipt: 'R-000051'),
        at: testT0,
      );
      writeMark(
        dir.path,
        HighWaterMark(
          backupName: 'old',
          takenAt: testT0,
          figures: figures(),
          build: build,
        ),
      );
      await marks().raise(figures(), at: testT0);
      expect(readMark(dir.path)!.figures.payments, 47);
    });

    test(
      'replaced exactly (an accepted restore lowers it on purpose)',
      () async {
        await marks().raise(
          figures(payments: 47, receipt: 'R-000051'),
          at: testT0,
        );
        final restored = HighWaterMark(
          backupName: 'restore accepted',
          takenAt: testT0,
          figures: figures(),
          build: build,
        );
        await marks().replace(restored);
        expect(readMark(dir.path)!.figures, figures());
        expect(readMark(second)!.figures, figures());
      },
    );

    test('the debug reset moves the second mark aside too', () async {
      await makeDatabase();
      await marks().raise(
        (await inspectDataFolder(dir.path)).live!.figures,
        at: testT0,
      );
      final folder = resetDatabaseFiles(
        dir.path,
        DateTime.utc(2026, 11, 24, 7, 20, 5),
        secondFolder: second,
      );
      final sep = Platform.pathSeparator;
      expect(File('$second$sep$markFileName').existsSync(), isFalse);
      expect(File('$folder${sep}second-$markFileName').existsSync(), isTrue);
    });
  });

  group('the debug reset', () {
    test('copies and checks first, then moves everything aside; nothing is '
        'deleted', () async {
      await makeDatabase();
      writeMark(
        dir.path,
        HighWaterMark(
          backupName: 'b',
          takenAt: testT0,
          figures: (await inspectDataFolder(dir.path)).live!.figures,
          build: AppBuild.current.stamp,
        ),
      );
      final original = File(at(databaseFileName)).readAsBytesSync();

      final folder = resetDatabaseFiles(
        dir.path,
        DateTime.utc(2026, 11, 24, 7, 20, 5),
      );
      // Named in Nairobi time (UTC+3).
      expect(folder, at('reset-20261124-102005'));
      expect(File(at(databaseFileName)).existsSync(), isFalse);
      expect(File(at(markFileName)).existsSync(), isFalse);
      final sep = Platform.pathSeparator;
      expect(File('$folder$sep$databaseFileName').readAsBytesSync(), original);
      expect(File('$folder$sep$markFileName').existsSync(), isTrue);
      expect(
        File('$folder${sep}copy$sep$databaseFileName').existsSync(),
        isTrue,
      );
    });

    test('a copy that fails its check stops the reset; the file stays', () {
      File(at(databaseFileName)).writeAsStringSync('not a database');
      expect(
        () => resetDatabaseFiles(dir.path, DateTime.utc(2026, 11, 24)),
        throwsA(isA<ResetRefused>()),
      );
      expect(File(at(databaseFileName)).readAsStringSync(), 'not a database');
    });
  });

  group('the lock', () {
    const me = LockHolder(
      exePath: r'C:\UB40\Desk\lodging_pos.exe',
      version: 'desk 1.1.0 (build 3)',
      since: '2026-11-24T04:20:00.000Z',
    );

    /// A second process trying the same lock; prints `locked` or `held`.
    /// With `hold`, it keeps the lock (writing [holder] into the file)
    /// until its input closes.
    Future<Process> other(String mode, {LockHolder? holder}) async {
      final script = File(at('other.dart'))
        ..writeAsStringSync('''
import 'dart:io';
Future<void> main(List<String> args) async {
  final file = File(args[0]).openSync(mode: FileMode.append);
  try {
    file.lockSync(FileLock.exclusive, $lockByteOffset, ${lockByteOffset + 1});
  } on FileSystemException {
    stdout.write('held');
    return;
  }
  if (args[1] == 'hold') {
    file.truncateSync(0);
    file.writeStringSync(args[2]);
    file.flushSync();
    stdout.write('locked');
    await stdin.drain<void>();
  } else {
    stdout.write('locked');
  }
}
''');
      return Process.start('dart', [
        script.path,
        at(lockFileName),
        mode,
        jsonEncode((holder ?? me).toJson()),
      ], runInShell: Platform.isWindows);
    }

    test('this copy takes it; another process can’t', () async {
      expect(lockDataFolder(dir.path, me), isNull);
      final p = await other('try');
      expect(await p.stdout.transform(utf8.decoder).join(), 'held');
      await p.exitCode;
    });

    test('another process holds it: who, from where', () async {
      const usb = LockHolder(
        exePath: r'D:\Release\lodging_pos.exe',
        version: 'desk 1.0.0 (build 2)',
        since: '2026-11-24T04:00:00.000Z',
      );
      File(at(lockFileName)).createSync();
      final p = await other('hold', holder: usb);
      final out = p.stdout.transform(utf8.decoder).asBroadcastStream();
      expect(await out.first, 'locked');
      final holder = lockDataFolder(dir.path, me);
      expect(holder?.exePath, usb.exePath);
      expect(holder?.version, usb.version);
      await p.stdin.close();
      await p.exitCode;
    });
  });
}
