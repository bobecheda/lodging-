import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/shifts/domain/drawer.dart';

DateTime nov(int day, int hour, [int minute = 0]) =>
    nairobiInstant(2026, 11, day, hour, minute);

void main() {
  group('the opening float comes from the drawer, never typed', () {
    test('none before the starting cash is counted', () {
      expect(openingFloatFrom(const []), isNull);
    });

    test('the latest anchor: the starting cash, then each closing count', () {
      final anchors = [
        DrawerAnchor(
          id: 'start',
          kind: AnchorKind.start,
          at: nov(19, 8),
          counted: 2000,
        ),
        DrawerAnchor(
          id: 's-1',
          kind: AnchorKind.close,
          at: nov(19, 20),
          counted: 6800,
        ),
      ];
      expect(openingFloatFrom(anchors)?.id, 's-1');
      expect(openingFloatFrom(anchors)?.balance, 6800);
      expect(openingFloatFrom(anchors.reversed)?.balance, 6800);
    });

    test('a collection leaves what was counted less what was taken', () {
      final a = DrawerAnchor(
        id: 'c',
        kind: AnchorKind.collect,
        at: nov(20, 9),
        counted: 9000,
        removed: 8000,
      );
      expect(a.balance, 1000);
    });
  });

  group('the chain: start → open → close → open …', () {
    final shifts = [
      ChainShift(
        id: 's-1',
        userName: 'Mary Desk',
        openedAt: nov(19, 8, 5),
        openingFloat: 2000,
        closedAt: nov(19, 20),
        expectedCash: 7000,
        firstCount: 6800,
        counted: 6800,
        needsReview: true,
        note: 'Gave change from my pocket',
      ),
      // Float as the drawer said: what s-1 counted.
      ChainShift(
        id: 's-2',
        userName: 'Mary Desk',
        openedAt: nov(20, 8),
        openingFloat: 6800,
        closedAt: nov(20, 20),
        expectedCash: 9000,
        firstCount: 8900,
        counted: 9000,
        needsReview: false,
      ),
      // A float that isn't the last count: a break.
      ChainShift(
        id: 's-3',
        userName: 'Grace Supervisor',
        openedAt: nov(21, 8),
        openingFloat: 5000,
      ),
    ];
    final starts = [
      DrawerStartRecord(
        id: 'd-1',
        at: nov(19, 8),
        counted: 2000,
        by: 'Grace Supervisor',
      ),
    ];
    final chain = drawerChain(shifts: shifts, starts: starts);

    test('newest first, every step in order', () {
      expect(
        [for (final e in chain) e.runtimeType],
        [
          ShiftOpenedEntry,
          ShiftClosedEntry,
          ShiftOpenedEntry,
          ShiftClosedEntry,
          ShiftOpenedEntry,
          DrawerStarted,
        ],
      );
    });

    test('each opening is checked against the count before it', () {
      final opens = chain.whereType<ShiftOpenedEntry>().toList();
      expect([for (final o in opens) o.shiftId], ['s-3', 's-2', 's-1']);
      expect([for (final o in opens) o.isBreak], [true, false, false]);
      expect(
        opens.first.detail,
        'Float KES 5,000, but the drawer should hold KES 9,000',
      );
      expect(opens[1].detail, 'Float KES 6,800');
    });

    test('a shift opened with no count before it is a break', () {
      final c = drawerChain(
        shifts: [
          ChainShift(
            id: 's-0',
            userName: 'Mary Desk',
            openedAt: nov(18, 8),
            openingFloat: 500,
          ),
        ],
        starts: const [],
      );
      final open = c.single as ShiftOpenedEntry;
      expect(open.isBreak, isTrue);
      expect(open.detail, 'Float KES 500, with no count before it');
    });

    test('each close: expected, counted, the gap, a recount match, review', () {
      final closes = chain.whereType<ShiftClosedEntry>().toList();
      final s1 = closes.last;
      expect(s1.gap, -200);
      expect(
        s1.detail,
        'Expected KES 7,000 · counted KES 6,800 · Short KES 200',
      );
      expect(s1.needsReview, isTrue);
      expect(s1.matchedOnRecount, isFalse);
      expect(s1.note, 'Gave change from my pocket');
      final s2 = closes.first;
      expect(s2.gap, 0);
      expect(s2.matchedOnRecount, isTrue);
      expect(s2.needsReview, isFalse);
    });

    test('the starting cash', () {
      final start = chain.last as DrawerStarted;
      expect(start.title, 'Starting cash counted');
      expect(start.detail, 'KES 2,000 · by Grace Supervisor');
    });
  });

  group('what the drawer should hold now', () {
    test('no count yet: unknown', () {
      expect(drawerExpectedNow(latest: null), isNull);
    });

    test('between shifts: the last count', () {
      expect(drawerExpectedNow(latest: 6800), 6800);
    });

    test('during a shift: its float plus its net cash', () {
      expect(
        drawerExpectedNow(latest: 6800, openFloat: 6800, openCashNet: 1400),
        8200,
      );
    });
  });
}
