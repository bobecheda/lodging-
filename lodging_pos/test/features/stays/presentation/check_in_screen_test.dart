import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount desk;
  late RoomsRepository rooms;

  setUp(() async {
    env = TestEnv(); // Wed 14 Oct 22:00 Nairobi
    supervisor = await env.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('desk');
    rooms = RoomsRepository(env.db, env.audit);
  });
  tearDown(() => env.close());

  /// Room [number]: Bed A Deluxe 700, and Bed B Comfort 600 if [twoBeds].
  Future<RoomSummary> room(String number, {bool twoBeds = false}) =>
      rooms.createRoom(
        supervisor,
        NewRoom(
          number: number,
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: twoBeds ? SeedIds.comfort : null,
        ),
      );

  Future<Guest> grace() => env.guests.register(
    desk,
    const GuestForm(
      fullName: 'Grace Achieng',
      phone: '0722418905',
      idType: IdType.nationalId,
      idNumber: '12343921',
    ),
  );

  /// The receptionist, signed in with her shift open, on the bed board.
  Future<ProviderContainer> deskOnBoard(WidgetTester tester) async {
    final shifts = ShiftRepository(env.db, env.audit);
    if (await shifts.openShiftOnThisDevice() == null) {
      await shifts.openShift(user: desk, openingFloat: 1000);
    }
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    expect(locationOf(app), Routes.home);
    return app;
  }

  Future<void> go(
    ProviderContainer app,
    String location,
    WidgetTester t,
  ) async {
    app.read(routerProvider).go(location);
    await t.pumpAndSettle();
  }

  Future<void> findGuest(WidgetTester tester, Guest g) async {
    await enterKey(tester, 'guests.search', '0722 418');
    await tester.pumpAndSettle();
    await tapKey(tester, 'guests.match.${g.id}');
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<TextButton>(
            find.descendant(
              of: find.byKey(const ValueKey('checkIn.save')),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed !=
      null;

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('from a Ready tile: returning guest, 2 nights, cash → saved, '
      'step 4, and the bed is In use on the board', (tester) async {
    await room('7');
    final g = await grace();
    // Another guest checked in first, so this receipt is the second.
    final r9 = await room('9');
    await env.checkIn(r9.beds.single.id, by: desk);
    final app = await deskOnBoard(tester);

    await tapKey(tester, 'board.bed.7A');
    expect(text(tester, 'checkIn.bed'), 'Room 7 · Bed A');
    expect(saveEnabled(tester), isFalse);
    expect(find.byKey(const ValueKey('checkIn.missing')), findsOneWidget);

    await findGuest(tester, g);
    expect(find.byKey(const ValueKey('guests.selected')), findsOneWidget);
    expect(find.text('RETURNING'), findsOneWidget);
    expect(find.text('No earlier stays'), findsOneWidget);

    await tapKey(tester, 'stepper.plus');
    expect(text(tester, 'checkIn.from'), 'Wed 14 Oct, 22:00');
    expect(text(tester, 'checkIn.until'), 'Fri 16 Oct, 10:00');
    expect(text(tester, 'checkIn.total'), 'KES 1,400');
    expect(find.text('2 × KES 700'), findsOneWidget);

    await tapKey(tester, 'choice.PaymentMethod.cash');
    expect(saveEnabled(tester), isTrue);
    await tapKey(tester, 'checkIn.save');

    expect(find.byKey(const ValueKey('checkIn.done')), findsOneWidget);
    expect(text(tester, 'receipt.number'), 'R-000002');
    expect(text(tester, 'receipt.room'), 'Room 7 · Bed A');
    expect(text(tester, 'receipt.total'), 'KES 1,400');
    expect(find.text('Cash'), findsWidgets);
    expect(find.byKey(const ValueKey('receipt.copy')), findsNothing);
    expect(
      find.byKey(const ValueKey('checkIn.step.4.current')),
      findsOneWidget,
    );

    await tapKey(tester, 'checkIn.done.board');
    expect(locationOf(app), Routes.home);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board.bed.7A')),
        matching: find.text('IN USE'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancelling leaves the bed Available; nothing is saved', (
    tester,
  ) async {
    await room('7');
    final g = await grace();
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await findGuest(tester, g);
    await tapKey(tester, 'choice.PaymentMethod.cash');
    await tapKey(tester, 'checkIn.back');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board.bed.7A')),
        matching: find.text('READY'),
      ),
      findsOneWidget,
    );
    expect(await env.db.select(env.db.stays).get(), isEmpty);
    expect(await env.db.select(env.db.payments).get(), isEmpty);
  });

  testWidgets('New check-in lists only Ready beds to choose from', (
    tester,
  ) async {
    await room('7');
    final r8 = await room('8');
    final stay = await env.checkIn(r8.beds.single.id, by: desk);
    await env.checkOut(stay, by: desk); // 8A needs cleaning
    await deskOnBoard(tester);
    await tapKey(tester, 'board.newCheckIn');

    expect(find.byKey(const ValueKey('checkIn.pick.7A')), findsOneWidget);
    expect(find.byKey(const ValueKey('checkIn.pick.8A')), findsNothing);
    await tapKey(tester, 'checkIn.pick.7A');
    expect(text(tester, 'checkIn.bed'), 'Room 7 · Bed A');
    await tapKey(tester, 'checkIn.changeBed');
    expect(find.byKey(const ValueKey('checkIn.pick.7A')), findsOneWidget);
  });

  testWidgets('whole room: both beds on one receipt; a Bed B that needs '
      'cleaning says so and can’t be added', (tester) async {
    final r7 = await room('7', twoBeds: true);
    final r8 = await room('8', twoBeds: true);
    final stay = await env.checkIn(r8.beds.last.id, by: desk);
    await env.checkOut(stay, by: desk);
    final g = await grace();
    final app = await deskOnBoard(tester);

    await go(app, Routes.checkInFor(r8.beds.first.id), tester);
    expect(find.text('Bed B needs cleaning first'), findsOneWidget);
    final box = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('checkIn.wholeRoom')),
    );
    expect(box.onChanged, isNull);

    await go(app, Routes.checkInFor(r7.beds.first.id), tester);
    await tapKey(tester, 'checkIn.wholeRoom');
    await findGuest(tester, g);
    expect(text(tester, 'checkIn.total'), 'KES 1,300');
    expect(find.text('Bed A · 1 × KES 700'), findsOneWidget);
    expect(find.text('Bed B · 1 × KES 600'), findsOneWidget);
    await tapKey(tester, 'choice.PaymentMethod.cash');
    await tapKey(tester, 'checkIn.save');

    expect(text(tester, 'receipt.room'), 'Room 7 · Beds A and B');
    expect(
      text(tester, 'checkIn.done.summary'),
      'Grace Achieng · Room 7, Beds A and B',
    );
    expect(
      await env.db.select(env.db.stays).get(),
      hasLength(3),
    ); // 8B + 7A, 7B
    final payments = await env.db.select(env.db.payments).get();
    expect(payments.last.amount, 1300);
  });

  testWidgets('a new guest is shown as NEW and saved only with the check-in', (
    tester,
  ) async {
    await room('7');
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await tapKey(tester, 'guests.register');
    await enterKey(tester, 'newGuest.fullName', 'Ann Wambui');
    await enterKey(tester, 'newGuest.phone', '0711 000 111');
    await tester.pumpAndSettle();
    await tapKey(tester, 'newGuest.save'); // "Use this guest"

    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('Registered when the check-in is saved'), findsOneWidget);
    expect(await env.db.select(env.db.guests).get(), isEmpty);

    await tapKey(tester, 'choice.PaymentMethod.cash');
    await tapKey(tester, 'checkIn.save');
    final guests = await env.db.select(env.db.guests).get();
    expect(guests.single.fullName, 'Ann Wambui');
    expect(find.byKey(const ValueKey('checkIn.done')), findsOneWidget);
  });

  testWidgets('M-Pesa: a used code is refused, saying where it was used', (
    tester,
  ) async {
    final r7 = await room('7');
    final r8 = await room('8');
    final g = await grace();
    final app = await deskOnBoard(tester);

    Future<void> payByMpesa(String bedId) async {
      await go(app, Routes.checkInFor(bedId), tester);
      await findGuest(tester, g);
      await tapKey(tester, 'choice.PaymentMethod.paybill');
      await enterKey(tester, 'checkIn.mpesaCode', 'qjk7h2lm4p');
      await tester.pumpAndSettle();
      await tapKey(tester, 'checkIn.save');
    }

    await payByMpesa(r7.beds.single.id);
    expect(text(tester, 'receipt.total'), 'KES 700');
    expect(find.text('QJK7H2LM4P'), findsOneWidget);
    await payByMpesa(r8.beds.single.id);
    expect(
      find.text(
        'QJK7H2LM4P was already used on receipt R-000001 (Wed 14 Oct, '
        '22:00).',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('checkIn.done')), findsNothing);
  });

  testWidgets('nights: typed, 1 to 30', (tester) async {
    await room('7');
    final g = await grace();
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await findGuest(tester, g);
    await tapKey(tester, 'choice.PaymentMethod.cash');

    await enterKey(tester, 'stepper.value', '10');
    await tester.pumpAndSettle();
    expect(text(tester, 'checkIn.total'), 'KES 7,000');
    expect(text(tester, 'checkIn.until'), 'Sat 24 Oct, 10:00');

    await enterKey(tester, 'stepper.value', '31');
    await tester.pumpAndSettle();
    expect(text(tester, 'checkIn.nightsError'), 'Choose 1 to 30 nights.');
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('a supervisor without a shift: Save is off with the note; Open '
      'shift goes to the shift screen and comes back', (tester) async {
    final r7 = await room('7');
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    // Signing in doesn't send a supervisor to the shift screen.
    expect(locationOf(app), Routes.home);

    await tapKey(tester, 'board.bed.7A');
    expect(
      find.text('Check-in takes a payment. Open a shift first.'),
      findsOneWidget,
    );
    expect(saveEnabled(tester), isFalse);

    await tapKey(tester, 'checkIn.openShift');
    expect(locationOf(app), Routes.shift);
    // Back returns without opening one.
    await tapKey(tester, 'shift.back');
    expect(locationOf(app), Routes.checkIn);

    await tapKey(tester, 'checkIn.openShift');
    await enterKey(tester, 'shift.float', '500');
    await tapKey(tester, 'shift.submit');
    expect(locationOf(app), Routes.checkIn);
    expect(
      app
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .queryParameters['bed'],
      r7.beds.single.id,
    );
    expect(find.byKey(const ValueKey('checkIn.noShift')), findsNothing);
    final shift = await ShiftRepository(
      env.db,
      env.audit,
    ).openShiftOnThisDevice();
    expect((shift!.userId, shift.openingFloat), (supervisor.id, 500));
  });
}
