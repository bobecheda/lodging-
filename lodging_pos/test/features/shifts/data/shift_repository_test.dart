import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/shifts/domain/drawer.dart';
import 'package:lodging_pos/features/shifts/domain/shift_close.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late ShiftRepository shifts;
  late UserAccount owner;
  late UserAccount supervisor;
  late UserAccount desk;

  setUp(() async {
    env = TestEnv();
    shifts = ShiftRepository(env.db, env.audit);
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    desk = await env.addReceptionist('mary');
  });
  tearDown(() => env.close());

  Future<List<DrawerEventRow>> drawerRows() =>
      env.db.select(env.db.drawerEvents).get();

  test('no shift is open on a fresh device', () async {
    expect(await shifts.openShiftOnThisDevice(), isNull);
    expect(await shifts.drawerStarted(), isFalse);
  });

  group('the starting cash (drawer.start)', () {
    test(
      'before it is counted, no shift opens and nothing is written',
      () async {
        await expectLater(
          shifts.openShift(user: desk),
          throwsA(isA<NoStartingCash>()),
        );
        expect(await shifts.openShiftOnThisDevice(), isNull);
        expect(await env.auditFor('shift.open'), isEmpty);
      },
    );

    test(
      'counted by the supervisor or owner, once; a receptionist can’t',
      () async {
        await expectLater(
          shifts.startDrawer(desk, counted: 2000),
          throwsA(isA<NotPermitted>()),
        );
        await expectLater(
          shifts.startDrawer(supervisor, counted: -1),
          throwsA(isA<DrawerRefused>()),
        );
        await shifts.startDrawer(supervisor, counted: 2000);
        final row = (await drawerRows()).single;
        expect(
          (row.kind, row.counted, row.countedBy, row.presentUser, row.expected),
          ('start', 2000, supervisor.id, null, null),
        );
        expect(
          (await env.auditFor('drawer.start')).single.userId,
          supervisor.id,
        );
        await expectLater(
          shifts.startDrawer(owner, counted: 5000),
          throwsA(
            isA<DrawerRefused>().having(
              (e) => e.message,
              'message',
              'The starting cash was already counted.',
            ),
          ),
        );
      },
    );
  });

  group('opening a shift: the float comes from the drawer', () {
    setUp(() => shifts.startDrawer(supervisor, counted: 2000));

    test('the starting cash, never typed; audited shift.open', () async {
      final opened = await shifts.openShift(user: desk);
      expect(opened.openingFloat, 2000);
      expect(opened.openedAt, env.clock.now());
      final row = await (env.db.select(
        env.db.shifts,
      )..where((s) => s.id.equals(opened.id))).getSingle();
      expect(row.openedFrom, (await drawerRows()).single.id);
      final entry = (await env.auditFor('shift.open')).single;
      expect(jsonDecode(entry.afterJson)['opening_float'], 2000);
    });

    test('only one shift can be open on a device', () async {
      final tom = await env.addReceptionist('tom');
      await shifts.openShift(user: desk);
      await expectLater(
        shifts.openShift(user: tom),
        throwsA(
          isA<ShiftAlreadyOpen>().having(
            (e) => e.shift.userId,
            'owner',
            desk.id,
          ),
        ),
      );
      expect(await env.auditFor('shift.open'), hasLength(1));
    });
  });

  group('closing a shift: the blind count (FD-11, Story B)', () {
    late String shiftId;
    late RoomSummary room;

    setUp(() async {
      await shifts.startDrawer(supervisor, counted: 2000);
      shiftId = (await shifts.openShift(user: desk)).id;
      room = await RoomsRepository(env.db, env.audit).createRoom(
        supervisor,
        const NewRoom(
          number: '7',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: SeedIds.comfort,
        ),
      );
      // KES 700 in cash on Mary's shift: the drawer should hold 2,700.
      await env.checkIn(room.beds.first.id, by: desk);
    });

    Future<ShiftRow> row() => (env.db.select(
      env.db.shifts,
    )..where((s) => s.id.equals(shiftId))).getSingle();

    test('a count that matches closes the shift; no review', () async {
      final result = await shifts.submitCount(desk, shiftId, 2700);
      expect(result, isA<CountClosed>());
      final s = await row();
      expect(s.status, 'closed');
      expect((s.expectedCash, s.expectedPaybill), (2700, 0));
      expect((s.firstCount, s.countedCash, s.variance), (2700, 2700, 0));
      expect((s.needsReview, s.closedBy, s.closeNote), (false, desk.id, null));
      expect(await env.auditFor('shift.close'), hasLength(1));
      expect(await shifts.openShiftOnThisDevice(), isNull);
    });

    test('a first count that doesn’t match is saved at once: leaving and '
        'coming back goes straight to the recount', () async {
      final result = await shifts.submitCount(desk, shiftId, 2600);
      expect(result, isA<CountAgain>());
      final s = await row();
      expect((s.status, s.firstCount, s.countedCash), ('open', 2600, null));
      final audit = (await env.auditFor('shift.count_mismatch')).single;
      expect(audit.userId, desk.id);
      // Another screen, another repository: still the recount.
      expect(
        await ShiftRepository(env.db, env.audit).countStageOf(shiftId),
        CountStage.recount,
      );
    });

    test('the recount matches: closed, matched only on recount', () async {
      await shifts.submitCount(desk, shiftId, 2600);
      final result = await shifts.submitCount(desk, shiftId, 2700);
      expect(result, isA<CountClosed>());
      final s = await row();
      expect((s.firstCount, s.countedCash, s.needsReview), (2600, 2700, false));
      expect(
        matchedOnRecount(
          firstCount: s.firstCount!,
          counted: s.countedCash!,
          needsReview: s.needsReview,
        ),
        isTrue,
      );
    });

    test('the recount doesn’t match either: no third count; a reason, then '
        'the shift closes anyway, needing review', () async {
      await shifts.submitCount(desk, shiftId, 2600);
      expect(
        await shifts.submitCount(desk, shiftId, 2650),
        isA<ReasonNeeded>(),
      );
      expect((await row()).countedCash, 2650);
      expect(await shifts.countStageOf(shiftId), CountStage.reason);
      await expectLater(
        shifts.submitCount(desk, shiftId, 2700),
        throwsA(isA<ShiftCloseRefused>()),
      );
      await expectLater(
        shifts.closeWithReason(desk, shiftId, '  '),
        throwsA(
          isA<ShiftCloseRefused>().having(
            (e) => e.message,
            'message',
            'Say why the count may be different.',
          ),
        ),
      );
      await shifts.closeWithReason(desk, shiftId, 'Gave change from my pocket');
      final s = await row();
      expect(s.status, 'closed');
      expect((s.firstCount, s.countedCash, s.variance), (2600, 2650, -50));
      expect(
        (s.needsReview, s.closeNote),
        (true, 'Gave change from my pocket'),
      );
    });

    test('a reason before two counts is refused', () async {
      await expectLater(
        shifts.closeWithReason(desk, shiftId, 'Just close it'),
        throwsA(isA<ShiftCloseRefused>()),
      );
      expect((await row()).status, 'open');
    });

    test('over is reviewed like short (tolerance 0)', () async {
      expect(await shifts.submitCount(desk, shiftId, 2800), isA<CountAgain>());
    });

    test('the tolerance: owner only, audited; then a count within it '
        'matches', () async {
      await expectLater(
        shifts.setCountTolerance(supervisor, 100),
        throwsA(isA<NotPermitted>()),
      );
      await expectLater(
        shifts.setCountTolerance(owner, -1),
        throwsA(isA<ArgumentError>()),
      );
      await shifts.setCountTolerance(owner, 100);
      expect((await env.auditFor('settings.update')).last.userId, owner.id);
      expect(await shifts.submitCount(desk, shiftId, 2650), isA<CountClosed>());
      expect((await row()).variance, -50);
    });

    test('the next shift’s float is this one’s closing count', () async {
      await shifts.submitCount(desk, shiftId, 2600);
      await shifts.submitCount(desk, shiftId, 2600);
      await shifts.closeWithReason(desk, shiftId, 'Counted twice');
      env.clock.advance(const Duration(hours: 1));
      final next = await shifts.openShift(user: desk);
      expect(next.openingFloat, 2600);
      final r = await (env.db.select(
        env.db.shifts,
      )..where((s) => s.id.equals(next.id))).getSingle();
      expect(r.openedFrom, shiftId);
    });

    test('a receptionist never gets the figures: the shift’s totals, the '
        'drawer now or the chain', () async {
      for (final call in <Future<Object?> Function()>[
        () => shifts.shiftFigures(desk, shiftId),
        () => shifts.drawerNow(desk),
        () => shifts.drawerChain(desk),
      ]) {
        await expectLater(call(), throwsA(isA<NotPermitted>()));
      }
      expect(can(desk, Permission.viewShiftTotals), isFalse);
      expect(
        (await shifts.shiftFigures(supervisor, shiftId)).cash.received,
        700,
      );
      expect(await shifts.drawerNow(owner), 2700);
    });

    test('someone else’s shift: the supervisor closes it blind too, recorded '
        'as theirs; another receptionist may not', () async {
      final tom = await env.addReceptionist('tom');
      await expectLater(
        shifts.submitCount(tom, shiftId, 2700),
        throwsA(isA<NotPermitted>()),
      );
      expect(
        await shifts.submitCount(supervisor, shiftId, 2600),
        isA<CountAgain>(),
      );
      await shifts.submitCount(supervisor, shiftId, 2700);
      expect((await row()).closedBy, supervisor.id);
      final s = (await shifts.watchShifts().first).single;
      expect(
        closedByLine(closer: s.closedByName!, owner: s.userName),
        'closed by Grace Supervisor for Desk MARY’s shift',
      );
    });

    test('a closed shift can’t be counted again or changed', () async {
      await shifts.submitCount(desk, shiftId, 2700);
      await expectLater(
        shifts.submitCount(desk, shiftId, 2700),
        throwsA(isA<ShiftCloseRefused>()),
      );
      await expectLater(
        env.db.customStatement(
          "UPDATE shifts SET status = 'open', closed_at = NULL, "
          "updated_at = '2030-01-01T00:00:00.000Z' WHERE id = ?",
          [shiftId],
        ),
        throwsA(anything),
      );
    });

    test('the chain: starting cash, the opening, the close', () async {
      await shifts.submitCount(desk, shiftId, 2600);
      await shifts.submitCount(desk, shiftId, 2700);
      final chain = await shifts.drawerChain(supervisor);
      expect(
        [for (final e in chain) e.runtimeType],
        [ShiftClosedEntry, ShiftOpenedEntry, DrawerStarted],
      );
      final close = chain.first as ShiftClosedEntry;
      expect((close.gap, close.matchedOnRecount), (0, true));
      expect((chain[1] as ShiftOpenedEntry).isBreak, isFalse);
    });

    test('the list: needs review and recount shown', () async {
      await shifts.submitCount(desk, shiftId, 2600);
      await shifts.submitCount(desk, shiftId, 2700);
      final s = (await shifts.watchShifts().first).single;
      expect((s.isOpen, s.takings, s.needsReview), (false, 700, false));
      expect(
        recountLine(s.firstCount!, s.counted!),
        'first count KES 2,600 → recounted KES 2,700',
      );
    });
  });
}
