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

    // The Now strip: the oldest overstay, and the beds to clean.
    final card = find.byKey(const ValueKey('board.overstayBar'));
    expect(
      find.descendant(of: card, matching: find.text('5 A · Kamau')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('1 h past 10:00')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('board.toClean.3A')), findsOneWidget);

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

  testWidgets('chips, category and search filter the board', (tester) async {
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

    Future<List<String>> roomsFor(String q) async {
      await enterKey(tester, 'board.search', q);
      await tester.pumpAndSettle();
      return [
        for (final n in ['1', '2', '10'])
          if (find.byKey(ValueKey('board.room.$n')).evaluate().isNotEmpty) n,
      ];
    }

    expect(await roomsFor('10'), ['10']);
    expect(await roomsFor('grace'), ['2']);
    expect(await roomsFor('0722 41'), ['2']);
    expect(await roomsFor('+254 722'), ['2']);
    expect(await roomsFor('nobody'), isEmpty);
    expect(find.text('No beds match.'), findsOneWidget);
    expect(await roomsFor(''), ['1', '2', '10']);
    // Phones are never shown on the board, masked or not.
    expect(find.textContaining('0722'), findsNothing);
  });

  testWidgets('"Guest or receipt": a receipt number lists the receipt under '
      'the box and opens it in Receipts; a name never does; "/" goes to the '
      'box (v2 PR 5)', (tester) async {
    final r2 = await room('2');
    final stay = await env.checkIn(r2.beds.single.id, by: supervisor);
    await nameGuest(stay, 'Grace Achieng', '0722418905');
    final number =
        (await env.db.select(env.db.payments).getSingle()).receiptNumber;
    final app = await openBoard(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'board.search');

    await enterKey(tester, 'board.search', 'Achieng');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board.receipts')), findsNothing);
    expect(find.byKey(const ValueKey('board.room.2')), findsOneWidget);

    await enterKey(tester, 'board.search', number);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board.receipts')), findsOneWidget);
    await tapKey(tester, 'board.receipt.$number');
    expect(locationOf(app), Routes.receipts);
  });

  testWidgets('"N" starts a new check-in, unless a field has the cursor', (
    tester,
  ) async {
    final app = await openBoard(tester);
    await enterKey(tester, 'board.search', '');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.home);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.checkIn);
    // The board's streams close on leaving: run their zero-length timers.
    await tester.pump(Duration.zero);
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
