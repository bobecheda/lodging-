import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/app/widgets/bed_status_tile.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late RoomsRepository rooms;

  setUp(() async {
    env = TestEnv(); // Wed 14 Oct 22:00 Nairobi
    supervisor = await env.createFirstSupervisor(testSetup);
    rooms = RoomsRepository(env.db, env.audit);
  });
  tearDown(() => env.close());

  Future<RoomSummary> room(String number, {bool twoBeds = false}) =>
      rooms.createRoom(
        supervisor,
        NewRoom(
          number: number,
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: twoBeds ? SeedIds.normal : null,
        ),
      );

  /// Gives the stay's guest a name and phone, as FD-4 would.
  Future<void> nameGuest(String stayId, String name, String phone) async {
    final stay = await (env.db.select(
      env.db.stays,
    )..where((s) => s.id.equals(stayId))).getSingle();
    await env.audit.writeWithAudit(
      action: 'guest.update',
      userId: supervisor.id,
      body: (w) => w.update(
        env.db.guests,
        stay.guestId,
        GuestsCompanion(fullName: Value(name), phone: Value(phone)),
      ),
    );
  }

  Future<ProviderContainer> openBoard(
    WidgetTester tester, {
    Duration? tick,
  }) async {
    env.boardTick = tick;
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    expect(locationOf(app), Routes.home);
    return app;
  }

  Finder tileText(String bed, String text) => find.descendant(
    of: find.byKey(ValueKey('board.bed.$bed')),
    matching: find.text(text),
  );

  BedTileStatus tileStatus(WidgetTester tester, String bed) => tester
      .widget<BedStatusTile>(find.byKey(ValueKey('board.bed.$bed')))
      .status;

  String chip(WidgetTester tester, String status) => tester
      .widget<Semantics>(
        find
            .descendant(
              of: find.byKey(ValueKey('board.chip.$status')),
              matching: find.byType(Semantics),
            )
            .first,
      )
      .properties
      .label!;

  testWidgets('no rooms yet says where to add them; New check-in opens '
      'check-in', (tester) async {
    final app = await openBoard(tester);
    expect(find.bySemanticsLabel(RegExp('^Bed board, ')), findsOneWidget);
    expect(find.textContaining('No rooms yet'), findsOneWidget);
    await tapKey(tester, 'board.newCheckIn');
    expect(locationOf(app), Routes.checkIn);
  });

  testWidgets('each status has its tile, line and count; an overstay is '
      'listed in the bar', (tester) async {
    final r1 = await room('1'); // Ready
    final r2 = await room('2'); // In use
    final r3 = await room('3'); // To clean (checked out)
    final r5 = await room('5'); // Overstay
    // Peter checked in yesterday for 1 night: paid to Thu 10:00.
    env.clock.set(nairobiInstant(2026, 10, 14, 13));
    final peter = await env.checkIn(r5.beds.single.id, by: supervisor);
    await nameGuest(peter, 'Peter Kamau', '0722418905');
    env.clock.set(nairobiInstant(2026, 10, 15, 11, 30)); // Thu 11:30
    final grace = await env.checkIn(
      r2.beds.single.id,
      by: supervisor,
      nights: 2,
    );
    await nameGuest(grace, 'Grace Achieng', '0711000111');
    final gone = await env.checkIn(r3.beds.single.id, by: supervisor);
    await env.checkOut(gone, by: supervisor);
    expect(r1.beds, hasLength(1));

    await openBoard(tester);
    // One line per tile (v2 PR 5): the surname and the paid-until weekday,
    // or how long past checkout.
    expect(tileText('1A', 'Ready'), findsOneWidget);
    expect(tileText('2A', 'Achieng · Sat'), findsOneWidget);
    expect(tileStatus(tester, '2A'), BedTileStatus.occupied);
    expect(tileText('3A', 'To clean'), findsOneWidget);
    expect(tileText('5A', 'Kamau · 1 h'), findsOneWidget);
    expect(tileStatus(tester, '5A'), BedTileStatus.overstay);

    // The Now strip: the overstay as a row (no buttons), and the beds to
    // clean as chips.
    final row = find.byKey(const ValueKey('board.overstay.5A'));
    expect(
      find.descendant(of: row, matching: find.text('5 A · Kamau')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('1 h')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('board.overstay.more')), findsNothing);
    expect(find.byKey(const ValueKey('board.toClean.3A')), findsOneWidget);
    expect(find.byKey(const ValueKey('board.toClean.more')), findsNothing);

    expect(chip(tester, 'all'), 'All, 4');
    expect(chip(tester, 'ready'), 'Ready, 1');
    expect(chip(tester, 'occupied'), 'Occupied, 1');
    expect(chip(tester, 'overstay'), 'Overstay, 1');
    expect(chip(tester, 'toClean'), 'To clean, 1');
  });

  testWidgets('a Ready tile starts a check-in on that bed; an In use tile '
      'opens its bed panel; a To clean tile its cleaning panel', (
    tester,
  ) async {
    final r1 = await room('1');
    final r2 = await room('2');
    final r3 = await room('3');
    await env.checkIn(r2.beds.single.id, by: supervisor);
    final gone = await env.checkIn(r3.beds.single.id, by: supervisor);
    await env.checkOut(gone, by: supervisor); // 3A needs cleaning
    final app = await openBoard(tester);

    await tapKey(tester, 'board.bed.3A');
    expect(find.byKey(const ValueKey('cleaning.title')), findsOneWidget);
    await tapKey(tester, 'cleaning.closeIcon');

    await tapKey(tester, 'board.bed.2A');
    expect(find.byKey(const ValueKey('panel.title')), findsOneWidget);
    await tapKey(tester, 'panel.close');
    expect(find.byKey(const ValueKey('panel.title')), findsNothing);

    await tapKey(tester, 'board.bed.1A');
    expect(locationOf(app), Routes.checkIn);
    expect(
      app
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .queryParameters['bed'],
      r1.beds.single.id,
    );
    expect(find.text('Room 1 · Bed A'), findsOneWidget);
  });

  testWidgets('chips and category filter the board', (tester) async {
    await room('1', twoBeds: true); // A Deluxe, B Normal
    final r2 = await room('2');
    final stay = await env.checkIn(r2.beds.single.id, by: supervisor);
    await nameGuest(stay, 'Grace Achieng', '0722418905');
    await room('10');
    await openBoard(tester);

    await tapKey(tester, 'board.chip.occupied');
    expect(find.byKey(const ValueKey('board.room.2')), findsOneWidget);
    expect(find.byKey(const ValueKey('board.room.1')), findsNothing);
    await tapKey(tester, 'board.chip.all');

    await tapKey(tester, 'board.category');
    await tapKey(tester, 'board.category.${SeedIds.normal}');
    expect(find.byKey(const ValueKey('board.bed.1B')), findsOneWidget);
    expect(find.byKey(const ValueKey('board.bed.1A')), findsNothing);
    expect(chip(tester, 'all'), 'All, 1');
    await tapKey(tester, 'board.category');
    await tapKey(tester, 'board.category.all');
    // Phones are never shown on the board, masked or not.
    expect(find.textContaining('0722'), findsNothing);
  });

  testWidgets('"N" starts a new check-in; there is no board search and '
      '"/" does nothing (dropped 25 Nov)', (tester) async {
    final app = await openBoard(tester);
    expect(find.byKey(const ValueKey('board.search')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.checkIn);
    // The board's streams close on leaving: run their zero-length timers.
    await tester.pump(Duration.zero);
  });

  testWidgets('the Now strip is a summary: 3 overstay rows, oldest first, '
      'and "Show all" in the title line; To clean chips hug their text, two lines '
      'at most, then "+ N more"', (tester) async {
    // 5 overstays, checked in an hour apart from Mon 12 Oct 08:00 (paid to
    // Tue 10:00); 32 beds checked out, to clean.
    final over = <RoomSummary>[];
    for (var i = 1; i <= 5; i++) {
      over.add(await room('$i'));
    }
    final dirty = <RoomSummary>[];
    for (var i = 21; i <= 52; i++) {
      dirty.add(await room('$i'));
    }
    for (final (i, r) in over.indexed) {
      env.clock.set(nairobiInstant(2026, 10, 12, 8 + i));
      await env.checkIn(r.beds.single.id, by: supervisor);
    }
    env.clock.set(nairobiInstant(2026, 10, 14, 21));
    for (final r in dirty) {
      final stay = await env.checkIn(r.beds.single.id, by: supervisor);
      await env.checkOut(stay, by: supervisor);
    }
    env.clock.set(nairobiInstant(2026, 10, 15, 12)); // Thu 12:00
    await openBoard(tester);

    for (final b in ['1A', '2A', '3A']) {
      expect(find.byKey(ValueKey('board.overstay.$b')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('board.overstay.4A')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board.overstay.1A')),
        matching: find.text('2 days'),
      ),
      findsOneWidget,
    );
    // "Overstay 5 · Show all" in the title line, no "+ N more" row.
    final showAll = find.byKey(const ValueKey('board.overstay.more'));
    expect(
      find.descendant(of: showAll, matching: find.text('Show all')),
      findsOneWidget,
    );
    expect(find.textContaining('more · Show all'), findsNothing);
    expect(
      tester.getCenter(showAll).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('board.overstay.1A'))).dy,
      ),
    );
    expect(tester.getSize(showAll).height, greaterThanOrEqualTo(44));
    // No buttons on the rows.
    expect(find.byKey(const ValueKey('board.overstay.extend')), findsNothing);

    // Chips hug their text: far narrower than the card.
    final card = tester.getSize(find.byKey(const ValueKey('board.toClean')));
    final chipSize = tester.getSize(
      find.byKey(const ValueKey('board.toClean.21A')),
    );
    expect(chipSize.width, lessThan(card.width / 4));
    expect(chipSize.height, 36);
    // Two lines at most, then "+ N more".
    final more = find.byKey(const ValueKey('board.toClean.more'));
    expect(more, findsOneWidget);
    final first = tester.getTopLeft(
      find.byKey(const ValueKey('board.toClean.21A')),
    );
    expect(tester.getTopLeft(more).dy - first.dy, lessThanOrEqualTo(36 + 8));

    await tapKey(tester, 'board.overstay.more');
    expect(chip(tester, 'overstay'), 'Overstay, 5');
    expect(find.byKey(const ValueKey('board.bed.21A')), findsNothing);
    expect(find.byKey(const ValueKey('board.bed.5A')), findsOneWidget);

    await tapKey(tester, 'board.chip.all');
    await tapKey(tester, 'board.toClean.more');
    expect(find.byKey(const ValueKey('board.bed.1A')), findsNothing);
    expect(find.byKey(const ValueKey('board.bed.21A')), findsOneWidget);
  });

  testWidgets('an overstay row opens its bed panel; a To clean chip its '
      'cleaning panel', (tester) async {
    final r5 = await room('5');
    final r6 = await room('6');
    await env.checkIn(r5.beds.single.id, by: supervisor);
    final gone = await env.checkIn(r6.beds.single.id, by: supervisor);
    await env.checkOut(gone, by: supervisor);
    env.clock.set(nairobiInstant(2026, 10, 15, 12)); // 5A: 2 h past 10:00
    await openBoard(tester);

    await tapKey(tester, 'board.overstay.5A');
    expect(find.byKey(const ValueKey('panel.title')), findsOneWidget);
    await tapKey(tester, 'panel.close');
    await tapKey(tester, 'board.toClean.6A');
    expect(find.byKey(const ValueKey('cleaning.title')), findsOneWidget);
  });

  testWidgets('a check-in shows at once (watched, no refresh)', (tester) async {
    final r4 = await room('4');
    // Opened now, so the check-in below writes once: a write inside
    // runAsync wakes the board's watched queries, which take the database
    // lock in fake time, and a later read inside runAsync would wait for
    // it forever.
    await env.openShift(supervisor, startingCash: 0);
    await openBoard(tester);
    expect(tileText('4A', 'Ready'), findsOneWidget);

    await tester.runAsync(() => env.checkIn(r4.beds.single.id, by: supervisor));
    await tester.pumpAndSettle();
    expect(tileStatus(tester, '4A'), BedTileStatus.occupied);
  });

  testWidgets('a bed turns Overstay on its own after paid_until + grace', (
    tester,
  ) async {
    final r5 = await room('5');
    // Wed 22:00 check-in, 1 night: paid to Thu 10:00, grace to 11:00.
    await env.checkIn(r5.beds.single.id, by: supervisor);
    env.clock.set(nairobiInstant(2026, 10, 15, 10, 59, 45));
    await openBoard(tester, tick: const Duration(seconds: 30));
    expect(tileStatus(tester, '5A'), BedTileStatus.occupied);
    expect(find.byKey(const ValueKey('board.overstayBar')), findsNothing);

    env.clock.advance(const Duration(seconds: 30)); // 11:00:15
    await tester.pump(const Duration(seconds: 30));
    expect(tileStatus(tester, '5A'), BedTileStatus.overstay);
    expect(find.byKey(const ValueKey('board.overstayBar')), findsOneWidget);

    // Leave the board so its ticker stops before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
