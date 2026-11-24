import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/app_version.dart';
import 'package:lodging_pos/core/database/desk_startup.dart';

/// The desk's startup checks (story/desk-db-guards, docs/backup-restore.md
/// "Startup checks"): pure rules over what the files hold.
void main() {
  const thisBuild = AppBuild(version: '1.1.0', build: 3, commit: 'abc1234');
  final t0 = DateTime.utc(2026, 11, 24, 4, 20);

  DatabaseFigures figures({
    int schema = 11,
    int stays = 42,
    int payments = 61,
    int audit = 900,
    String? receipt = 'R-000061',
    DateTime? lastAudit,
  }) => DatabaseFigures(
    schemaVersion: schema,
    stays: stays,
    payments: payments,
    auditEntries: audit,
    lastReceipt: receipt,
    lastAuditAt: lastAudit ?? t0,
  );

  HighWaterMark mark([DatabaseFigures? f]) => HighWaterMark(
    backupName: 'lodging_pos-2026-11-24-0720.sqlite',
    takenAt: t0,
    figures: f ?? figures(),
    build: thisBuild.stamp,
  );

  StartupVerdict judge({
    LiveFile? live,
    bool hasBackups = false,
    HighWaterMark? mark,
    LockHolder? heldBy,
    AppBuild build = thisBuild,
    int schema = 11,
  }) => judgeStartup(
    DeskInspection(
      live: live,
      hasBackups: hasBackups,
      mark: mark,
      heldBy: heldBy,
    ),
    build: build,
    schemaVersion: schema,
  );

  LiveFile live([DatabaseFigures? f, DeskStamp? stamp]) =>
      LiveFile(figures: f ?? figures(), stamp: stamp ?? thisBuild.stamp);

  group('the lock', () {
    test('another copy holds it: refused before anything else', () {
      const holder = LockHolder(
        exePath: r'D:\Release\lodging_pos.exe',
        version: 'desk 1.0.0 (build 2)',
        since: '2026-11-24T04:00:00.000Z',
      );
      final v = judge(heldBy: holder, live: live());
      expect(v, isA<AlreadyOpen>());
      expect((v as AlreadyOpen).holder.exePath, r'D:\Release\lodging_pos.exe');
    });
  });

  group('a missing file', () {
    test('nothing around it: a first run', () {
      expect(judge(), isA<StartOk>());
    });

    test('backups (or copies, or a mark) exist: refused, never a silent '
        'first run', () {
      expect(judge(hasBackups: true), isA<DatabaseMissing>());
      expect(judge(mark: mark()), isA<DatabaseMissing>());
    });
  });

  group('versions', () {
    test('a newer schema is refused, naming both sides', () {
      final v = judge(
        live: live(
          figures(schema: 12),
          const DeskStamp(version: '1.2.0', build: 4),
        ),
      );
      expect(v, isA<NewerDatabase>());
      final message = refusalMessage(v, thisBuild, schemaVersion: 11);
      expect(message, contains('v12'));
      expect(message, contains('desk 1.2.0 (build 4)'));
      expect(message, contains('desk 1.1.0 (build 3)'));
      expect(message, contains('v11'));
    });

    test('a newer build stamp is refused even at the same schema', () {
      final v = judge(
        live: live(figures(), const DeskStamp(version: '1.2.0', build: 4)),
      );
      expect(v, isA<NewerBuild>());
      expect(
        refusalMessage(v, thisBuild, schemaVersion: 11),
        allOf(
          contains('desk 1.2.0 (build 4)'),
          contains('desk 1.1.0 (build 3)'),
        ),
      );
    });

    test('an older or equal stamp, or none, is fine', () {
      expect(
        judge(
          live: live(figures(), const DeskStamp(version: '1.0.0', build: 2)),
        ),
        isA<StartOk>(),
      );
      expect(judge(live: LiveFile(figures: figures())), isA<StartOk>());
      expect(judge(live: live()), isA<StartOk>());
    });

    test('an older schema is upgraded as before (no refusal by itself)', () {
      expect(judge(live: live(figures(schema: 9))), isA<StartOk>());
    });
  });

  group('the high-water mark', () {
    test('no mark yet: nothing to compare', () {
      expect(judge(live: live(figures(stays: 0))), isA<StartOk>());
    });

    test('equal or more: fine', () {
      expect(judge(live: live(), mark: mark()), isA<StartOk>());
      expect(
        judge(
          live: live(
            figures(
              stays: 43,
              payments: 62,
              audit: 950,
              receipt: 'R-000062',
              lastAudit: t0.add(const Duration(hours: 1)),
            ),
          ),
          mark: mark(),
        ),
        isA<StartOk>(),
      );
    });

    for (final (what, older) in [
      ('schema', figures(schema: 10)),
      ('stays', figures(stays: 41)),
      ('payments', figures(payments: 60)),
      ('audit entries', figures(audit: 899)),
      ('last receipt', figures(receipt: 'R-000060')),
      ('no receipt at all', figures(receipt: null)),
      (
        'last audit time',
        figures(lastAudit: t0.subtract(const Duration(minutes: 1))),
      ),
    ]) {
      test('fewer $what: refused as older than the last backup', () {
        final v = judge(live: live(older), mark: mark());
        expect(v, isA<OlderThanBackup>(), reason: what);
      });
    }

    test('the message names both sides', () {
      final v = judge(
        live: live(
          figures(
            stays: 30,
            payments: 46,
            audit: 711,
            receipt: 'R-000050',
            lastAudit: DateTime.utc(2026, 11, 11, 8, 3),
          ),
        ),
        mark: mark(),
      );
      final message = refusalMessage(v, thisBuild, schemaVersion: 11);
      expect(message, contains('30 stays'));
      expect(message, contains('42 stays'));
      expect(message, contains('R-000050'));
      expect(message, contains('R-000061'));
      expect(message, contains('desk 1.1.0 (build 3)'));
    });

    test('receipt serials compare as numbers, whatever the prefix', () {
      expect(receiptSerial('R-000061'), 61);
      expect(receiptSerial('UB-001200'), 1200);
      expect(receiptSerial(null), 0);
      expect(receiptSerial('nonsense'), 0);
    });

    test('figures and the mark survive JSON', () {
      final m = HighWaterMark(
        backupName: 'b.sqlite',
        takenAt: t0,
        figures: figures(),
        build: thisBuild.stamp,
        pendingRestore: PendingRestore(
          acceptedBy: 'owner-1',
          acceptedAt: t0,
          counterFloor: 62,
          previous: figures(stays: 50),
        ),
      );
      final back = HighWaterMark.fromJson(m.toJson());
      expect(back.figures, m.figures);
      expect(back.takenAt, t0);
      expect(back.build, thisBuild.stamp);
      expect(back.pendingRestore!.counterFloor, 62);
      expect(back.pendingRestore!.previous.stays, 50);
    });
  });

  group('where the app runs from', () {
    test('the recorded folder on a fixed drive: fine', () {
      expect(
        judgeLocation(
          exeFolder: r'C:\UB40\Desk',
          removable: false,
          recorded: r'c:\ub40\desk\',
        ),
        isA<LocationOk>(),
      );
    });

    test('nothing recorded yet on a fixed drive: record it', () {
      final l = judgeLocation(
        exeFolder: r'C:\UB40\Desk',
        removable: false,
        recorded: null,
      );
      expect(l, isA<LocationRecord>());
      expect((l as LocationRecord).path, r'C:\UB40\Desk');
    });

    test('a removable drive: a warning, recorded or not', () {
      for (final recorded in [null, r'C:\UB40\Desk']) {
        final l = judgeLocation(
          exeFolder: r'D:\Release',
          removable: true,
          recorded: recorded,
        );
        expect(l, isA<UnusualLocation>());
        expect((l as UnusualLocation).removable, isTrue);
      }
    });

    test('another folder than the recorded one: a warning', () {
      final l = judgeLocation(
        exeFolder: r'C:\Users\HP\Desktop\old',
        removable: false,
        recorded: r'C:\UB40\Desk',
      );
      expect(l, isA<UnusualLocation>());
      expect((l as UnusualLocation).recorded, r'C:\UB40\Desk');
      expect(l.removable, isFalse);
    });
  });

  test('the version line', () {
    expect(
      versionLine(thisBuild, schemaVersion: 11),
      'Desk 1.1.0 (build 3) · abc1234 · database v11',
    );
  });
}
