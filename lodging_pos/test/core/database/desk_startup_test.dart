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
    HighWaterMark? secondMark,
    LockHolder? heldBy,
    AppBuild build = thisBuild,
    int schema = 11,
  }) => judgeStartup(
    DeskInspection(
      live: live,
      hasBackups: hasBackups,
      mark: mark,
      secondMark: secondMark,
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

  group('the mark moves with the work (story/desk-db-guards-2)', () {
    test('the actions that move it: receipts, shifts and the drawer', () {
      for (final action in [
        'payment.create',
        'refund.pay',
        'shift.open',
        'shift.close',
        'drawer.start',
        'drawer.check',
        'drawer.collect',
      ]) {
        expect(movesMark({action}), isTrue, reason: action);
      }
      expect(movesMark({'user.login', 'guest.create'}), isFalse);
      expect(movesMark({'stay.check_in', 'payment.create'}), isTrue);
      expect(movesMark(const {}), isFalse);
    });

    test('highest: each figure at its highest of the two', () {
      final a = figures(stays: 43, payments: 60, receipt: 'R-000059');
      final b = figures(
        audit: 950,
        receipt: 'R-000062',
        lastAudit: t0.add(const Duration(hours: 1)),
      );
      final h = DatabaseFigures.highest(a, b);
      expect(h.stays, 43);
      expect(h.payments, 61);
      expect(h.auditEntries, 950);
      expect(h.lastReceipt, 'R-000062');
      expect(h.lastAuditAt, t0.add(const Duration(hours: 1)));
      expect(DatabaseFigures.highest(a, null), a);
    });

    test('raising never lowers it, keeps the last backup and a pending '
        'restore, and says when the desk last held it', () {
      final pending = PendingRestore(
        acceptedBy: 'owner-1',
        acceptedAt: t0,
        counterFloor: 62,
        previous: figures(),
      );
      final before = HighWaterMark(
        backupName: 'lodging_pos-2026-11-24-0720.sqlite',
        takenAt: t0,
        figures: figures(),
        build: thisBuild.stamp,
        pendingRestore: pending,
      );
      final later = t0.add(const Duration(minutes: 5));
      final raised = HighWaterMark.raised(
        before,
        figures(payments: 62, receipt: 'R-000062', stays: 40),
        at: later,
        build: thisBuild.stamp,
      );
      expect(raised.figures.payments, 62);
      expect(raised.figures.lastReceipt, 'R-000062');
      expect(raised.figures.stays, 42, reason: 'never lowered');
      expect(raised.backupName, before.backupName);
      expect(raised.takenAt, t0);
      expect(raised.heldAt, later);
      expect(raised.pendingRestore, same(pending));

      final backup = HighWaterMark.raised(
        raised,
        figures(),
        at: later,
        build: thisBuild.stamp,
        backupName: 'lodging_pos-2026-11-24-0725.sqlite',
      );
      expect(backup.backupName, 'lodging_pos-2026-11-24-0725.sqlite');
      expect(backup.takenAt, later);
      expect(backup.figures.payments, 62, reason: 'a backup never lowers it');

      final first = HighWaterMark.raised(
        null,
        figures(),
        at: t0,
        build: thisBuild.stamp,
      );
      expect(first.backupName, isNull);
      expect(first.figures, figures());
      expect(HighWaterMark.fromJson(first.toJson()).heldAt, t0);
    });

    test('the second mark (outside the data folder) refuses an older file '
        'even when the data folder came back with its own old mark', () {
      final old = figures(payments: 46, receipt: 'R-000050');
      final v = judge(live: live(old), mark: mark(old), secondMark: mark());
      expect(v, isA<OlderThanBackup>());
      expect((v as OlderThanBackup).mark.figures.payments, 61);
      expect(
        judge(live: live(old), mark: mark(), secondMark: mark(old)),
        isA<OlderThanBackup>(),
      );
      expect(
        judge(live: live(), mark: mark(), secondMark: mark()),
        isA<StartOk>(),
      );
    });

    test('a missing file with only the second mark left: never a silent '
        'first run', () {
      expect(judge(secondMark: mark()), isA<DatabaseMissing>());
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
