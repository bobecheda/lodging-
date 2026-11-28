import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/app_version.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database_files_native.dart';
import 'package:lodging_pos/core/database/desk_startup.dart';
import 'package:lodging_pos/core/database/mark_keeper.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/settings/settings_repository.dart';
import 'package:lodging_pos/core/sync/desk_behind.dart';
import 'package:lodging_pos/core/sync/desk_secret_store.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_store.dart';
import 'package:lodging_pos/features/backup/data/backup_service.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fake_cloud.dart';
import '../../../helpers/fixtures.dart';

/// The 24 Nov case, end to end with real files (story/desk-db-guards-2):
/// the desk works and syncs, backs up at 11:03, works and syncs again (a new
/// shift, a receipt), and then its live file is replaced by that backup.
/// Each guard must catch it: the mark offline, the second mark when the
/// whole data folder came back, the cloud when both marks are gone; and
/// no receipt number is ever sent twice.
void main() {
  late Directory root;
  late String data;
  late String second;
  late FakeCloud cloud;
  late MemoryDeskSecretStore secrets;
  late String backupName;

  String live() => '$data${Platform.pathSeparator}$databaseFileName';
  String markIn(String folder) =>
      '$folder${Platform.pathSeparator}$markFileName';
  DeskStamp build() => AppBuild.current.stamp;

  /// A session of the desk on the live file, with the real mark keeper.
  Future<(TestEnv, SyncEngine)> open(DateTime at) async {
    final env = TestEnv(executor: NativeDatabase(File(live())));
    env.clock.set(at);
    env.owner = (await env.users.findByUsername(testOwner.username))?.account;
    env.audit.onCommitted = MarkKeeper(
      env.db,
      MarkFiles(data, second, build: build()),
      env.clock,
    ).afterCommit;
    final engine = SyncEngine(
      db: env.db,
      audit: env.audit,
      cloud: cloud,
      secrets: secrets,
      clock: env.clock,
    );
    await engine.start();
    return (env, engine);
  }

  Future<void> close(TestEnv env, SyncEngine engine) async {
    await engine.dispose();
    await env.close();
  }

  Future<UserAccount> supervisorOf(TestEnv env) async =>
      (await env.users.findByUsername('supervisor'))!.account;

  Future<String> bed(TestEnv env, String number) async =>
      (await RoomsRepository(env.db, env.audit).createRoom(
        await supervisorOf(env),
        NewRoom(
          number: number,
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      )).beds.single.id;

  Future<DeskInspection> inspect() =>
      inspectDataFolder(data, secondFolder: second);

  StartupVerdict judge(DeskInspection i) => judgeStartup(
    i,
    build: AppBuild.current,
    schemaVersion: latestSchemaVersion,
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('restore_after_sync');
    data = '${root.path}${Platform.pathSeparator}data';
    Directory(data).createSync(recursive: true);
    second = '${root.path}${Platform.pathSeparator}local';
    cloud = FakeCloud();
    secrets = MemoryDeskSecretStore();

    // Wed 11 Nov: connected, a guest in, everything sent.
    final first = TestEnv(executor: NativeDatabase(File(live())));
    first.clock.set(nairobiInstant(2026, 11, 11, 10));
    await first.createFirstSupervisor(testSetup);
    await first.close();
    var (env, engine) = await open(nairobiInstant(2026, 11, 11, 10, 30));
    cloud.serverNow = () => env.clock.now();
    await engine.connect(
      owner: (await env.users.findByUsername(testOwner.username))!.account,
      installCode: 'ABCD-EFGH-JKLM',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );
    final supervisor = await supervisorOf(env);
    await env.checkIn(await bed(env, 'A1'), by: supervisor);
    await engine.syncNow();

    // 11:03: the backup.
    env.clock.set(nairobiInstant(2026, 11, 11, 11, 3));
    final backups = '$data${Platform.pathSeparator}backups';
    backupName = (await BackupService(
      env.db,
      env.audit,
      env.clock,
      SettingsRepository(env.db),
      folder: backups,
      marks: MarkFiles(data, second, build: build()),
    ).backUp(reason: BackupReason.daily)).file.name;

    // 11:06: more work, sent: a guest in A2 (a new receipt).
    env.clock.set(nairobiInstant(2026, 11, 11, 11, 6));
    await env.checkIn(await bed(env, 'A2'), by: supervisor);
    await engine.syncNow();
    expect(await SyncStore(env.db).unsent(limit: 10), isEmpty);
    expect(
      cloud.row(
        'payments',
        (await env.db.select(env.db.payments).get()).last.id,
      ),
      isNotNull,
    );
    await close(env, engine);

    // 24 Nov: the live file replaced by the 11:03 backup.
    for (final side in ['-wal', '-shm']) {
      final f = File('${live()}$side');
      if (f.existsSync()) f.deleteSync();
    }
    File('$backups${Platform.pathSeparator}$backupName').copySync(live());
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // A failed test left a file open; the temp folder is left behind.
    }
  });

  test('offline: the mark refuses it before anything opens', () async {
    final v = judge(await inspect());
    expect(v, isA<OlderThanBackup>());
    expect(
      (v as OlderThanBackup).mark.figures.payments,
      greaterThan(v.live.figures.payments),
    );
  });

  test('the whole data folder came back, its old mark too: the second mark '
      'refuses it', () async {
    final old = await inspect();
    writeMark(
      data,
      HighWaterMark(
        backupName: backupName,
        takenAt: nairobiInstant(2026, 11, 11, 11, 3),
        figures: old.live!.figures,
        build: build(),
      ),
    );
    final i = await inspect();
    expect(i.mark!.figures, i.live!.figures, reason: 'the old mark passes');
    expect(judge(i), isA<OlderThanBackup>());
  });

  test('both marks gone, online: the startup cloud check proves it, audited; '
      'nothing is sent', () async {
    File(markIn(data)).deleteSync();
    File(markIn(second)).deleteSync();
    expect(judge(await inspect()), isA<StartOk>());

    final pushes = cloud.pushes.length;
    final (env, engine) = await open(nairobiInstant(2026, 11, 24, 9, 51));
    final evidence = (await engine.checkCloud())!;
    expect(evidence.reasons, [
      BehindReason.missingRecords,
      BehindReason.higherReceipt,
    ]);
    expect(engine.status.phase, SyncPhase.behind);
    expect(await env.auditFor('desk.behind_cloud'), hasLength(1));
    await engine.syncNow();
    expect(cloud.pushes.length, pushes);
    await close(env, engine);
  });

  test('both marks gone, offline: it opens, but the engine asks the cloud '
      'before sending anything, so no receipt number goes up twice', () async {
    File(markIn(data)).deleteSync();
    File(markIn(second)).deleteSync();
    cloud.offline = true;
    final (env, engine) = await open(nairobiInstant(2026, 11, 24, 9, 51));
    final supervisor = await supervisorOf(env);
    // The 24 Nov guest, given the receipt number 11:06 already used.
    await env.checkIn(await bed(env, 'A9'), by: supervisor);
    final reused = (await env.db.select(env.db.payments).get())
        .map((p) => p.receiptNumber)
        .reduce((a, b) => receiptSerial(a) > receiptSerial(b) ? a : b);
    await engine.syncNow();
    expect(engine.status.phase, SyncPhase.offline);

    cloud.offline = false;
    final pushes = cloud.pushes.length;
    await engine.syncNow();
    expect(engine.status.phase, SyncPhase.behind);
    expect(cloud.pushes.length, pushes, reason: 'nothing sent');
    final inCloud = [
      for (final p in cloud.tables['payments']!.values)
        if (p['receipt_number'] == reused) p,
    ];
    expect(inCloud, hasLength(1), reason: 'only the 11:06 one');
    await close(env, engine);
  });
}
