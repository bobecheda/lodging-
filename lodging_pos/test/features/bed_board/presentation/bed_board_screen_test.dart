import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late RoomsRepository rooms;

  setUp(() async {
    env = TestEnv(); // Wed 14 Oct 22:00 Nairobi
    owner = await env.users.createFirstAdmin(testSetup);
    rooms = RoomsRepository(env.db, env.audit);
  });
  tearDown(() => env.close());

  Future<RoomSummary> room(String number, {bool twoBeds = false}) =>
      rooms.createRoom(
        owner,
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
      userId: owner.id,
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
    await signInAs(tester, 'owner', 'owner-pass');
    expect(locationOf(app), Routes.home);
    return app;
  }

  Finder tileText(String bed, String text) => find.descendant(
    of: find.byKey(ValueKey('board.bed.$bed')),
    matching: find.text(text),
  );

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
    expect(find.text('Bed board'), findsWidgets);
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
    final peter = await env.checkIn(r5.beds.single.id, by: owner);
    await nameGuest(peter, 'Peter Kamau', '0722418905');
    env.clock.set(nairobiInstant(2026, 10, 15, 11, 30)); // Thu 11:30
    final grace = await env.checkIn(r2.beds.single.id, by: owner, nights: 2);
    await nameGuest(grace, 'Grace Achieng', '0711000111');
    final gone = await env.checkIn(r3.beds.single.id, by: owner);
    await env.checkOut(gone, by: owner);
    expect(r1.beds, hasLength(1));

    await openBoard(tester);
    expect(tileText('1A', 'READY'), findsOneWidget);
    expect(tileText('1A', 'Deluxe'), findsOneWidget);
    expect(tileText('1A', 'KES 700 / night'), findsOneWidget);

    expect(tileText('2A', 'IN USE'), findsOneWidget);
    expect(tileText('2A', 'Grace Achieng'), findsOneWidget);
    expect(tileText('2A', 'until Sat 10:00 · Deluxe'), findsOneWidget);

    expect(tileText('3A', 'TO CLEAN'), findsOneWidget);
    expect(tileText('3A', 'Needs cleaning · assign'), findsOneWidget);

    expect(tileText('5A', 'OVERSTAY'), findsOneWidget);
    expect(tileText('5A', 'paid to Thu 10:00 · Deluxe'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board.overstayBar')),
        matching: find.textContaining(
          'Overstay · Room 5, Bed A · Peter Kamau',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );

    expect(chip(tester, 'all'), 'All beds, 4');
    expect(chip(tester, 'ready'), 'Ready, 1');
    expect(chip(tester, 'occupied'), 'Occupied, 1');
    expect(chip(tester, 'overstay'), 'Overstay, 1');
    expect(chip(tester, 'toClean'), 'Needs cleaning, 1');
  });

  testWidgets('a Ready tile starts a check-in on that bed; an In use tile '
      'opens its bed panel; a To clean tile its cleaning panel', (
    tester,
  ) async {
    final r1 = await room('1');
    final r2 = await room('2');
    final r3 = await room('3');
    await env.checkIn(r2.beds.single.id, by: owner);
    final gone = await env.checkIn(r3.beds.single.id, by: owner);
    await env.checkOut(gone, by: owner); // 3A needs cleaning
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
    final stay = await env.checkIn(r2.beds.single.id, by: owner);
    await nameGuest(stay, 'Grace Achieng', '0722418905');
    await room('10');
    await openBoard(tester);

    await tapKey(tester, 'board.chip.occupied');
    expect(find.byKey(const ValueKey('board.room.2')), findsOneWidget);
    expect(find.byKey(const ValueKey('board.room.1')), findsNothing);
    await tapKey(tester, 'board.chip.all');

    await tapKey(tester, 'board.category');
    await tester.tap(find.text('Normal').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board.bed.1B')), findsOneWidget);
    expect(find.byKey(const ValueKey('board.bed.1A')), findsNothing);
    expect(chip(tester, 'all'), 'All beds, 1');
    await tapKey(tester, 'board.category');
    await tester.tap(find.text('All categories').last);
    await tester.pumpAndSettle();

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

  testWidgets('a check-in shows at once (watched, no refresh)', (tester) async {
    final r4 = await room('4');
    // Opened now, so the check-in below writes once: a write inside
    // runAsync wakes the board's watched queries, which take the database
    // lock in fake time, and a later read inside runAsync would wait for
    // it forever.
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: owner, openingFloat: 0);
    await openBoard(tester);
    expect(tileText('4A', 'READY'), findsOneWidget);

    await tester.runAsync(() => env.checkIn(r4.beds.single.id, by: owner));
    await tester.pumpAndSettle();
    expect(tileText('4A', 'IN USE'), findsOneWidget);
  });

  testWidgets('a bed turns Overstay on its own after paid_until + grace', (
    tester,
  ) async {
    final r5 = await room('5');
    // Wed 22:00 check-in, 1 night: paid to Thu 10:00, grace to 11:00.
    await env.checkIn(r5.beds.single.id, by: owner);
    env.clock.set(nairobiInstant(2026, 10, 15, 10, 59, 45));
    await openBoard(tester, tick: const Duration(seconds: 30));
    expect(tileText('5A', 'IN USE'), findsOneWidget);
    expect(find.byKey(const ValueKey('board.overstayBar')), findsNothing);

    env.clock.advance(const Duration(seconds: 30)); // 11:00:15
    await tester.pump(const Duration(seconds: 30));
    expect(tileText('5A', 'OVERSTAY'), findsOneWidget);
    expect(find.byKey(const ValueKey('board.overstayBar')), findsOneWidget);

    // Leave the board so its ticker stops before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
