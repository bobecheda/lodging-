import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/app_version.dart';
import 'package:lodging_pos/core/database/desk_meta.dart';
import 'package:lodging_pos/core/database/desk_startup.dart';
import 'package:lodging_pos/features/backup/data/restore_acceptance.dart';

import '../../../helpers/fixtures.dart';

/// Accepting an older backup as the live database (story/desk-db-guards,
/// docs/backup-restore.md "Restoring an older backup"): the owner only,
/// never on a desk that has synced (until the cloud check), and the
/// receipt counter moves past every number already printed.
void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  final t0 = DateTime.utc(2026, 11, 24, 4, 20);
  DatabaseFigures figures({int stays = 30, String receipt = 'R-000050'}) =>
      DatabaseFigures(
        schemaVersion: 11,
        stays: stays,
        payments: stays,
        auditEntries: 700,
        lastReceipt: receipt,
        lastAuditAt: t0,
      );

  OlderThanBackup refusal({bool connected = false, int next = 51}) =>
      OlderThanBackup(
        LiveFile(
          figures: figures(),
          everConnected: connected,
          nextReceiptNumber: next,
        ),
        HighWaterMark(
          backupName: 'lodging_pos-2026-11-24-0720.sqlite',
          takenAt: t0,
          figures: figures(stays: 42, receipt: 'R-000061'),
          build: AppBuild.current.stamp,
        ),
      );

  group('accepting', () {
    late List<HighWaterMark> written;
    late bool deskConnected;
    late RestoreAcceptance acceptance;

    setUp(() async {
      await env.createFirstSupervisor(testSetup);
      final owner = await env.users.findByUsername('owner');
      written = [];
      deskConnected = false;
      acceptance = RestoreAcceptance(
        readOwner: () async => RestoreOwner(
          id: owner!.account.id,
          passwordHash: owner.passwordHash,
          isActive: true,
        ),
        hasher: env.hasher,
        deskConnected: () async => deskConnected,
        writeMark: (m) async => written.add(m),
        clock: env.clock,
      );
    });

    test('the owner’s password and the last paper receipt: a pending '
        'restore whose counter passes every number printed', () async {
      await acceptance.accept(
        refusal(),
        password: 'owner-pass',
        lastPaperReceipt: 'R-000064',
      );
      final mark = written.single;
      expect(mark.figures, figures()); // the restored file is the new mark
      final pending = mark.pendingRestore!;
      expect(pending.acceptedBy, env.owner!.id);
      expect(pending.counterFloor, 65); // past the paper's 64
      expect(pending.previous.stays, 42);
    });

    test('the floor is never below the last backup’s receipt', () async {
      await acceptance.accept(
        refusal(),
        password: 'owner-pass',
        lastPaperReceipt: '55',
      );
      expect(written.single.pendingRestore!.counterFloor, 62); // R-000061 + 1
    });

    test('a wrong password: refused, nothing written', () async {
      await expectLater(
        acceptance.accept(refusal(), password: 'nope', lastPaperReceipt: '64'),
        throwsA(isA<RestoreRefused>()),
      );
      expect(written, isEmpty);
    });

    test('no paper receipt number: refused', () async {
      await expectLater(
        acceptance.accept(
          refusal(),
          password: 'owner-pass',
          lastPaperReceipt: ' ',
        ),
        throwsA(isA<RestoreRefused>()),
      );
    });

    test('a desk that has synced waits for the cloud check: the restored '
        'file says so, or the desk still has its cloud key', () async {
      await expectLater(
        acceptance.accept(
          refusal(connected: true),
          password: 'owner-pass',
          lastPaperReceipt: '64',
        ),
        throwsA(isA<RestoreNeedsCloud>()),
      );
      deskConnected = true;
      await expectLater(
        acceptance.accept(
          refusal(),
          password: 'owner-pass',
          lastPaperReceipt: '64',
        ),
        throwsA(isA<RestoreNeedsCloud>()),
      );
      expect(written, isEmpty);
    });
  });

  group('applying it once the file opens', () {
    test(
      'raises the counter, audits it, then clears the pending part',
      () async {
        await env.createFirstSupervisor(testSetup);
        final mark = HighWaterMark(
          backupName: 'restore accepted',
          takenAt: t0,
          figures: figures(),
          build: AppBuild.current.stamp,
          pendingRestore: PendingRestore(
            acceptedBy: env.owner!.id,
            acceptedAt: t0,
            counterFloor: 65,
            previous: figures(stays: 42, receipt: 'R-000061'),
          ),
        );
        final written = <HighWaterMark>[];
        await applyPendingRestore(
          env.db,
          env.audit,
          mark,
          writeMark: (m) async => written.add(m),
        );
        expect(await raiseReceiptCounter(env.db, 1), (65, 65));
        final audit = (await env.auditFor('database.restore_accepted')).single;
        expect(audit.userId, env.owner!.id);
        expect(audit.afterJson, contains('"counter_before":1'));
        expect(audit.afterJson, contains('"counter_after":65'));
        expect(written.single.pendingRestore, isNull);
        expect(written.single.figures, figures());
      },
    );
  });
}
