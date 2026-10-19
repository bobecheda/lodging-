import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/shifts/domain/shift_close.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late ShiftRepository shifts;

  setUp(() {
    env = TestEnv();
    shifts = ShiftRepository(env.db, env.audit);
  });
  tearDown(() => env.close());

  test('no shift is open on a fresh device', () async {
    expect(await shifts.openShiftOnThisDevice(), isNull);
  });

  test('opening a shift records the float and audits shift.open', () async {
    final desk = await env.addReceptionist('desk');
    final opened = await shifts.openShift(user: desk, openingFloat: 1500);
    expect(opened.openingFloat, 1500);
    expect(opened.openedAt, env.clock.now());
    expect(opened.userName, desk.fullName);

    final current = (await shifts.openShiftOnThisDevice())!;
    expect(current.id, opened.id);
    expect(current.userId, desk.id);
    expect(current.userName, desk.fullName);

    final entry = (await env.auditFor('shift.open')).single;
    expect(entry.userId, desk.id);
    expect(jsonDecode(entry.afterJson)['opening_float'], 1500);
  });

  test('a zero float is allowed', () async {
    final desk = await env.addReceptionist('desk');
    expect(
      (await shifts.openShift(user: desk, openingFloat: 0)).openingFloat,
      0,
    );
  });

  test('a negative float is rejected without writing', () async {
    final desk = await env.addReceptionist('desk');
    await expectLater(
      shifts.openShift(user: desk, openingFloat: -1),
      throwsArgumentError,
    );
    expect(await shifts.openShiftOnThisDevice(), isNull);
  });

  test('only one shift can be open on a device', () async {
    final desk = await env.addReceptionist('desk');
    final tom = await env.addReceptionist('tom');
    await shifts.openShift(user: desk, openingFloat: 1000);
    await expectLater(
      shifts.openShift(user: tom, openingFloat: 500),
      throwsA(
        isA<ShiftAlreadyOpen>().having((e) => e.shift.userId, 'owner', desk.id),
      ),
    );
    expect(await env.auditFor('shift.open'), hasLength(1));
  });

  group('closing a shift (FD-11)', () {
    late UserAccount owner;
    late UserAccount desk;
    late String shiftId;

    setUp(() async {
      owner = await env.users.createFirstAdmin(testSetup);
      desk = await env.addReceptionist('mary');
      shiftId = (await shifts.openShift(user: desk, openingFloat: 1000)).id;
      // KES 700 in cash, taken on Mary's shift.
      final room = await RoomsRepository(env.db, env.audit).createRoom(
        owner,
        const NewRoom(
          number: '7',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      );
      await env.checkIn(room.beds.single.id, by: desk);
    });

    Future<CloseFigures> close({
      UserAccount? by,
      int first = 1700,
      int counted = 1700,
      String note = '',
      ShiftTakings? shown,
    }) async => shifts.closeShift(
      by ?? desk,
      shiftId,
      firstCount: first,
      counted: counted,
      note: note,
      shown: shown ?? await shifts.takings(shiftId),
    );

    Future<ShiftRow> row() => (env.db.select(
      env.db.shifts,
    )..where((s) => s.id.equals(shiftId))).getSingle();

    test('saves expected, both counts, the variance, the note and who '
        'closed it; audited with both counts', () async {
      final f = await close(first: 1500, counted: 1650, note: 'Recounted');
      expect((f.expectedCash, f.variance), (1700, -50));
      final s = await row();
      expect(s.status, 'closed');
      expect(s.closedAt, env.clock.now());
      expect((s.expectedCash, s.expectedPaybill), (1700, 0));
      expect((s.firstCount, s.countedCash, s.variance), (1500, 1650, -50));
      expect((s.closeNote, s.closedBy), ('Recounted', desk.id));
      final audit = (await env.auditFor('shift.close')).single;
      final after = jsonDecode(audit.afterJson) as Map;
      expect((after['first_count'], after['counted_cash']), (1500, 1650));
      expect(await shifts.openShiftOnThisDevice(), isNull);
    });

    test('exact: no note needed; short or over: a note is', () async {
      await expectLater(
        close(counted: 1500, first: 1500),
        throwsA(
          isA<ShiftCloseRefused>().having(
            (e) => e.message,
            'message',
            'Say why the cash is short.',
          ),
        ),
      );
      expect((await row()).status, 'open');
      await close();
      expect((await row()).closeNote, isNull);
    });

    test('a payment since the review stops the close', () async {
      final shown = await shifts.takings(shiftId);
      final room = await RoomsRepository(env.db, env.audit).createRoom(
        owner,
        const NewRoom(
          number: '8',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      );
      await env.checkIn(room.beds.single.id, by: desk);
      await expectLater(
        close(shown: shown),
        throwsA(
          isA<ShiftCloseRefused>().having(
            (e) => e.message,
            'message',
            contains('A payment came in since you counted'),
          ),
        ),
      );
    });

    test('someone else’s shift: the owner may (closeOtherShifts), recorded '
        'as theirs; a receptionist may not', () async {
      final tom = await env.addReceptionist('tom');
      await expectLater(close(by: tom), throwsA(isA<NotPermitted>()));
      await close(by: owner);
      expect((await row()).closedBy, owner.id);
      final list = await shifts.watchShifts().first;
      final s = list.single;
      expect(s.closedByName, owner.fullName);
      expect(
        closedByLine(closer: s.closedByName!, owner: s.userName),
        'closed by Grace Owner for Desk MARY’s shift',
      );
    });

    test(
      'a closed shift can’t be closed again or changed (v5 trigger)',
      () async {
        await close();
        await expectLater(close(), throwsA(isA<ShiftCloseRefused>()));
        await expectLater(
          env.db.customStatement(
            "UPDATE shifts SET status = 'open', closed_at = NULL, "
            "updated_at = '2030-01-01T00:00:00.000Z' WHERE id = ?",
            [shiftId],
          ),
          throwsA(anything),
        );
        expect((await row()).status, 'closed');
      },
    );

    test(
      'the owner’s list: newest first, open and closed, with takings',
      () async {
        await close(first: 1600, counted: 1700);
        final s = (await shifts.watchShifts().first).single;
        expect(s.isOpen, isFalse);
        expect(s.takings, 700);
        expect(
          recountLine(s.firstCount!, s.counted!),
          'first count KES 1,600 → recounted KES 1,700',
        );
      },
    );
  });
}
