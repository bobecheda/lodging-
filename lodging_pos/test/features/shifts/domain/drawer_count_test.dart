import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/shifts/domain/drawer.dart';
import 'package:lodging_pos/features/shifts/domain/shift_close.dart';

DateTime nov(int day, int hour, [int minute = 0]) =>
    nairobiInstant(2026, 11, day, hour, minute);

void main() {
  group('what the drawer should hold: the last count plus cash since', () {
    final close = DrawerAnchor(
      id: 's-1',
      kind: AnchorKind.close,
      at: nov(19, 20),
      counted: 2000,
    );
    final moves = [
      CashMove(at: nov(19, 19), amount: 700), // before the anchor: in it
      CashMove(at: nov(20, 9), amount: 1400),
      CashMove(at: nov(20, 11), amount: -600), // a cash refund paid out
      CashMove(at: nov(20, 15), amount: 700),
    ];

    test('only cash after the anchor, up to the moment', () {
      expect(expectedAt(anchor: close, moves: moves, at: nov(20, 12)), 2800);
      expect(expectedAt(anchor: close, moves: moves, at: nov(20, 16)), 3500);
    });

    test('a check mid-shift is a new anchor: later cash adds to its count', () {
      final check = DrawerAnchor(
        id: 'd-1',
        kind: AnchorKind.check,
        at: nov(20, 12),
        counted: 2700, // 100 short of 2,800
      );
      expect(expectedAt(anchor: check, moves: moves, at: nov(20, 16)), 3400);
    });

    test('a collection leaves its count less what was taken', () {
      final collect = DrawerAnchor(
        id: 'd-2',
        kind: AnchorKind.collect,
        at: nov(20, 12),
        counted: 2800,
        removed: 2500,
      );
      expect(expectedAt(anchor: collect, moves: moves, at: nov(20, 16)), 1000);
      expect(openingFloatFrom([close, collect])?.balance, 300);
    });
  });

  group('a drawer count: blind, one recount, then a reason', () {
    test('the first count matches: recorded as it is', () {
      final c = drawerCountOf(expected: 2800, firstCount: 2800);
      expect((c.firstCount, c.counted, c.needsReview), (2800, 2800, false));
    });

    test('a recount after a matching first count is refused (no third '
        'count, no second either)', () {
      expect(
        () => drawerCountOf(expected: 2800, firstCount: 2800, recount: 2700),
        throwsA(isA<DrawerCountProblem>()),
      );
    });

    test('the first count misses: a recount is needed', () {
      expect(
        () => drawerCountOf(expected: 2800, firstCount: 2700),
        throwsA(
          isA<DrawerCountProblem>().having(
            (e) => e.message,
            'message',
            countAgainMessage,
          ),
        ),
      );
    });

    test('the recount matches: no review, the first count kept', () {
      final c = drawerCountOf(expected: 2800, firstCount: 2700, recount: 2800);
      expect((c.firstCount, c.counted, c.needsReview), (2700, 2800, false));
    });

    test('the recount misses too: a reason, then it needs review', () {
      expect(
        () => drawerCountOf(expected: 2800, firstCount: 2700, recount: 2750),
        throwsA(
          isA<DrawerCountProblem>().having(
            (e) => e.message,
            'message',
            'Say why the count may be different.',
          ),
        ),
      );
      final c = drawerCountOf(
        expected: 2800,
        firstCount: 2700,
        recount: 2750,
        note: '  Counted twice  ',
      );
      expect((c.counted, c.needsReview, c.note), (2750, true, 'Counted twice'));
    });

    test('over is reviewed like short; the tolerance applies', () {
      expect(
        () => drawerCountOf(expected: 2800, firstCount: 2900),
        throwsA(isA<DrawerCountProblem>()),
      );
      expect(
        drawerCountOf(expected: 2800, firstCount: 2850, tolerance: 50).counted,
        2850,
      );
    });

    test('a negative count is refused', () {
      expect(
        () => drawerCountOf(expected: 0, firstCount: -1),
        throwsA(isA<DrawerCountProblem>()),
      );
      expect(
        () => drawerCountOf(expected: 0, firstCount: 10, recount: -1),
        throwsA(isA<DrawerCountProblem>()),
      );
    });
  });

  group('what a collection takes away', () {
    test('zero up to what was counted; never negative, never more', () {
      expect(removedError(0, counted: 2800), isNull);
      expect(removedError(2800, counted: 2800), isNull);
      expect(removedError(null, counted: 2800), 'Enter the cash taken away.');
      expect(removedError(-1, counted: 2800), 'The amount can’t be negative.');
      expect(
        removedError(2801, counted: 2800),
        'You can’t take away more than you counted.',
      );
    });
  });

  group('checks and collections in the chain', () {
    final shifts = [
      ChainShift(
        id: 's-1',
        userName: 'Mary Desk',
        openedAt: nov(20, 8),
        openingFloat: 2000,
        closedAt: nov(20, 20),
        expectedCash: 1400 + 2600,
        firstCount: 4000,
        counted: 4000,
      ),
      // Opened from the collection: 4,000 counted, 3,000 taken.
      ChainShift(
        id: 's-2',
        userName: 'Mary Desk',
        openedAt: nov(21, 8),
        openingFloat: 1000,
      ),
    ];
    final counts = [
      DrawerCountRecord(
        id: 'd-1',
        kind: DrawerCountKind.check,
        at: nov(20, 12),
        expected: 2800,
        firstCount: 2700,
        counted: 2600,
        needsReview: true,
        note: 'Change from my pocket',
        by: 'Amina Owner',
        present: 'Mary Desk',
      ),
      DrawerCountRecord(
        id: 'd-2',
        kind: DrawerCountKind.collect,
        at: nov(20, 21),
        expected: 4000,
        firstCount: 4000,
        counted: 4000,
        removed: 3000,
        by: 'Grace Supervisor',
        present: 'Mary Desk',
      ),
    ];
    final chain = drawerChain(
      shifts: shifts,
      starts: [
        DrawerStartRecord(
          id: 'd-0',
          at: nov(20, 7),
          counted: 2000,
          by: 'Grace Supervisor',
        ),
      ],
      counts: counts,
    );

    test('in order, newest first', () {
      expect(
        [for (final e in chain) e.runtimeType],
        [
          ShiftOpenedEntry,
          CashCollected,
          ShiftClosedEntry,
          DrawerChecked,
          ShiftOpenedEntry,
          DrawerStarted,
        ],
      );
    });

    test('a check: who, with whom, the gap, needs review', () {
      final check = chain.whereType<DrawerChecked>().single;
      expect(check.title, 'Amina Owner checked the drawer, Mary Desk present');
      expect(
        check.detail,
        'Expected KES 2,800 · counted KES 2,600 · Short KES 200',
      );
      expect((check.gap, check.needsReview), (-200, true));
      expect(check.note, 'Change from my pocket');
    });

    test('a collection: what was taken and what was left', () {
      final c = chain.whereType<CashCollected>().single;
      expect(c.title, 'Grace Supervisor collected cash, Mary Desk present');
      expect(
        c.detail,
        'Expected KES 4,000 · counted KES 4,000 · Exact · KES 3,000 '
        'taken, KES 1,000 left',
      );
    });

    test('the next float follows the collection: no break', () {
      final next = chain.first as ShiftOpenedEntry;
      expect((next.float, next.isBreak), (1000, false));
    });

    test('the week since the last collection, for the collector', () {
      final week = sinceLastCollection(chain);
      // Everything after the previous collection (none): the whole chain
      // below the newest collection, closes, checks and openings.
      expect(week.closes, 1);
      expect(week.checks, 1);
      expect(week.reviews, 1);
      expect(week.recountMatches, 0);
    });
  });
}
