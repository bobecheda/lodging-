import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/widgets/bed_status_tile.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

/// The v2 check-in (PR 6, Figma "Desk · Check-in (full)" and "Check-in ·
/// variants"): every function of the old one, restyled.
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
      await env.openShift(desk, startingCash: 1000);
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

  Future<void> search(WidgetTester tester, String text) async {
    await enterKey(tester, 'checkIn.guestSearch', text);
    await tester.pumpAndSettle();
  }

  Future<void> findGuest(WidgetTester tester, Guest g) async {
    await search(tester, '0722 418');
    await tapKey(tester, 'checkIn.match.${g.id}');
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

  String field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  testWidgets('from a Ready tile: returning guest, 2 nights, cash → saved, '
      'the receipt, and the bed is In use on the board', (tester) async {
    await room('7');
    final g = await grace();
    // Another guest checked in first, so this receipt is the second.
    final r9 = await room('9');
    await env.checkIn(r9.beds.single.id, by: desk);
    final app = await deskOnBoard(tester);

    await tapKey(tester, 'board.bed.7A');
    expect(text(tester, 'checkIn.bed'), '7 A');
    expect(text(tester, 'checkIn.bedMeta'), 'Deluxe · KES 700 a night');
    expect(saveEnabled(tester), isFalse);
    expect(text(tester, 'checkIn.confirmLine'), 'Find or add the guest');

    // Matches mask the phone; the chosen guest shows it in full.
    await search(tester, '0722 418');
    expect(
      find.descendant(
        of: find.byKey(ValueKey('checkIn.match.${g.id}')),
        matching: find.text('0722 ••• 905 · National ID ••••3921'),
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'checkIn.match.${g.id}');
    expect(find.byKey(const ValueKey('checkIn.guest')), findsOneWidget);
    expect(
      text(tester, 'checkIn.guest.line'),
      '0722 418 905 · National ID ••••3921 · No stays yet',
    );
    expect(find.byKey(ValueKey('checkIn.match.${g.id}')), findsNothing);

    await tapKey(tester, 'stepper.plus');
    expect(text(tester, 'checkIn.out'), 'Out Fri 16 Oct, 10:00');
    expect(text(tester, 'checkIn.total'), 'KES 1,400');
    expect(text(tester, 'checkIn.priceLine.0'), '2 nights × KES 700');

    // No payment method is chosen at the start.
    expect(text(tester, 'checkIn.confirmLine'), 'Choose Cash or M-Pesa');
    expect(saveEnabled(tester), isFalse);
    await tapKey(tester, 'choice.PaymentMethod.cash');
    expect(
      text(tester, 'checkIn.confirmLine'),
      'Cash · KES 1,400 · out Fri 10:00',
    );
    expect(saveEnabled(tester), isTrue);
    await tapKey(tester, 'checkIn.save');

    expect(find.byKey(const ValueKey('checkIn.done')), findsOneWidget);
    expect(text(tester, 'receipt.number'), 'R-000002');
    expect(text(tester, 'receipt.room'), 'Room 7 · Bed A');
    expect(text(tester, 'receipt.total'), 'KES 1,400');
    expect(find.byKey(const ValueKey('receipt.copy')), findsNothing);

    await tapKey(tester, 'checkIn.done.board');
    expect(locationOf(app), Routes.home);
    expect(
      tester
          .widget<BedStatusTile>(find.byKey(const ValueKey('board.bed.7A')))
          .status,
      BedTileStatus.occupied,
    );
  });

  testWidgets('"Not this guest" clears the choice', (tester) async {
    await room('7');
    final g = await grace();
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await findGuest(tester, g);
    await tapKey(tester, 'checkIn.notThisGuest');
    expect(find.byKey(const ValueKey('checkIn.guest')), findsNothing);
    expect(find.byKey(ValueKey('checkIn.match.${g.id}')), findsOneWidget);
    expect(text(tester, 'checkIn.confirmLine'), 'Find or add the guest');
  });

  testWidgets('Cancel leaves the bed Available; nothing is saved', (
    tester,
  ) async {
    await room('7');
    final g = await grace();
    final app = await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await findGuest(tester, g);
    await tapKey(tester, 'choice.PaymentMethod.cash');
    await tapKey(tester, 'checkIn.cancel');

    expect(locationOf(app), Routes.home);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board.bed.7A')),
        matching: find.text('Ready'),
      ),
      findsOneWidget,
    );
    expect(await env.db.select(env.db.stays).get(), isEmpty);
    expect(await env.db.select(env.db.payments).get(), isEmpty);
  });

  testWidgets('New check-in: "Choose a bed" opens the chooser, which lists '
      'only Ready and clean beds', (tester) async {
    await room('7');
    final r8 = await room('8');
    final stay = await env.checkIn(r8.beds.single.id, by: desk);
    await env.checkOut(stay, by: desk); // 8A needs cleaning
    await deskOnBoard(tester);
    await tapKey(tester, 'board.newCheckIn');

    expect(text(tester, 'checkIn.bed'), 'Choose a bed');
    expect(text(tester, 'checkIn.confirmLine'), 'Choose a bed');
    await tapKey(tester, 'checkIn.changeBed');
    expect(text(tester, 'checkIn.chooser.count'), 'Ready beds · 1');
    expect(find.byKey(const ValueKey('checkIn.pick.7A')), findsOneWidget);
    expect(find.byKey(const ValueKey('checkIn.pick.8A')), findsNothing);
    expect(find.text('Only Ready and clean beds are listed.'), findsOneWidget);
    await tapKey(tester, 'checkIn.pick.7A');
    expect(find.byKey(const ValueKey('checkIn.chooser')), findsNothing);
    expect(text(tester, 'checkIn.bed'), '7 A');

    // Change opens it again; Escape closes it and keeps the bed.
    await tapKey(tester, 'checkIn.changeBed');
    expect(find.byKey(const ValueKey('checkIn.pick.7A')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checkIn.chooser')), findsNothing);
    expect(text(tester, 'checkIn.bed'), '7 A');
  });

  testWidgets('whole room: both beds on one receipt; a room whose other bed '
      'needs cleaning says so and can’t be switched on', (tester) async {
    final r7 = await room('7', twoBeds: true);
    final r8 = await room('8', twoBeds: true);
    final stay = await env.checkIn(r8.beds.last.id, by: desk);
    await env.checkOut(stay, by: desk);
    final g = await grace();
    final app = await deskOnBoard(tester);

    await go(app, Routes.checkInFor(r8.beds.first.id), tester);
    expect(text(tester, 'checkIn.wholeRoomNote'), '· 8 B needs cleaning first');
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('checkIn.wholeRoom')))
          .onChanged,
      isNull,
    );

    await go(app, Routes.checkInFor(r7.beds.first.id), tester);
    expect(find.text('Whole room (7 A + B)'), findsOneWidget);
    await tapKey(tester, 'checkIn.wholeRoom');
    expect(text(tester, 'checkIn.bed'), '7 A + 7 B');
    expect(text(tester, 'checkIn.bedMeta'), 'KES 700 + KES 600 a night');
    await findGuest(tester, g);
    expect(text(tester, 'checkIn.total'), 'KES 1,300');
    expect(text(tester, 'checkIn.priceLine.0'), '7 A · 1 night × KES 700');
    expect(
      text(tester, 'checkIn.priceLine.1'),
      '7 B · 1 night × KES 600 · one receipt',
    );
    await tapKey(tester, 'choice.PaymentMethod.cash');
    expect(
      text(tester, 'checkIn.confirmLine'),
      'Cash · KES 1,300 · 2 beds · out Thu 10:00',
    );
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

  testWidgets('no match: the new guest form, Phone filled from the search; '
      'the guest is saved only with the check-in', (tester) async {
    await room('7');
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await search(tester, '0711 000 111');

    expect(
      find.text('No guest with this phone or ID — new guest'),
      findsOneWidget,
    );
    expect(field(tester, 'checkIn.newGuest.phone'), '0711 000 111');
    expect(field(tester, 'checkIn.newGuest.idNumber'), '');
    expect(
      text(tester, 'checkIn.confirmLine'),
      'Add the new guest’s name and phone',
    );
    // No ID type is chosen until tapped.
    expect(
      find.byKey(const ValueKey('checkIn.idType.national_id.on')),
      findsNothing,
    );

    await enterKey(tester, 'checkIn.newGuest.fullName', 'Ann Wambui');
    await tester.pumpAndSettle();
    await tapKey(tester, 'choice.PaymentMethod.cash');
    expect(await env.db.select(env.db.guests).get(), isEmpty);
    await tapKey(tester, 'checkIn.save');

    final guests = await env.db.select(env.db.guests).get();
    expect(
      (guests.single.fullName, guests.single.phone),
      ('Ann Wambui', '0711000111'),
    );
    expect(find.byKey(const ValueKey('checkIn.done')), findsOneWidget);
  });

  testWidgets('an ID search fills ID number; a typed ID needs its type; a '
      'registered ID names its guest and "Use this guest" takes her', (
    tester,
  ) async {
    await room('7');
    final g = await grace();
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.7A');

    await search(tester, '3418 2297');
    expect(field(tester, 'checkIn.newGuest.idNumber'), '3418 2297');
    expect(field(tester, 'checkIn.newGuest.phone'), '');

    await search(tester, '0733 120 455');
    expect(field(tester, 'checkIn.newGuest.phone'), '0733 120 455');
    await enterKey(tester, 'checkIn.newGuest.fullName', 'Tom Otieno');
    await enterKey(tester, 'checkIn.newGuest.idNumber', '12343921');
    await tester.pumpAndSettle();
    await tapKey(tester, 'choice.PaymentMethod.cash');
    await tapKey(tester, 'checkIn.save');
    expect(find.text('Choose the ID type.'), findsOneWidget);
    expect(find.byKey(const ValueKey('checkIn.done')), findsNothing);

    await tapKey(tester, 'checkIn.idType.national_id');
    await tapKey(tester, 'checkIn.save');
    expect(
      text(tester, 'checkIn.idTaken'),
      'This National ID is already registered to Grace Achieng · '
      '0722 ••• 905.',
    );
    expect(find.byKey(const ValueKey('checkIn.done')), findsNothing);

    await tapKey(tester, 'checkIn.useTakenGuest');
    expect(find.byKey(const ValueKey('checkIn.guest')), findsOneWidget);
    expect(find.text('Grace Achieng'), findsOneWidget);
    await tapKey(tester, 'checkIn.save');
    expect(find.byKey(const ValueKey('checkIn.done')), findsOneWidget);
    final guests = await env.db.select(env.db.guests).get();
    expect(guests.single.id, g.id);
  });

  testWidgets('"New guest with this phone": a family member sharing a phone, '
      'with the shared-phone notice', (tester) async {
    await room('7');
    final g = await grace();
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await search(tester, '0722 418 905');
    expect(find.byKey(ValueKey('checkIn.match.${g.id}')), findsOneWidget);

    await tapKey(tester, 'checkIn.newGuestWithPhone');
    expect(field(tester, 'checkIn.newGuest.phone'), '0722 418 905');
    expect(
      find.textContaining('Already registered with this phone: Grace Achieng'),
      findsOneWidget,
    );
    await enterKey(tester, 'checkIn.newGuest.fullName', 'Tom Achieng');
    await tester.pumpAndSettle();
    await tapKey(tester, 'choice.PaymentMethod.cash');
    await tapKey(tester, 'checkIn.save');

    expect(find.byKey(const ValueKey('checkIn.done')), findsOneWidget);
    final guests = await env.db.select(env.db.guests).get();
    expect(guests.map((g) => g.fullName), {'Grace Achieng', 'Tom Achieng'});
  });

  testWidgets('M-Pesa: the code field only for M-Pesa; a used code is '
      'refused, saying where it was used', (tester) async {
    final r7 = await room('7');
    final r8 = await room('8');
    final g = await grace();
    final app = await deskOnBoard(tester);

    Future<void> payByMpesa(String bedId) async {
      await go(app, Routes.checkInFor(bedId), tester);
      await findGuest(tester, g);
      expect(find.byKey(const ValueKey('checkIn.mpesaCode')), findsNothing);
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
    expect(text(tester, 'checkIn.out'), 'Out Sat 24 Oct, 10:00');

    await enterKey(tester, 'stepper.value', '31');
    await tester.pumpAndSettle();
    expect(text(tester, 'checkIn.nightsError'), 'Choose 1 to 30 nights.');
    expect(text(tester, 'checkIn.confirmLine'), 'Choose 1 to 30 nights.');
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('a supervisor without a shift: "Open your shift first" '
      'instead of the form; Open shift goes to the shift screen and comes '
      'back to the same bed', (tester) async {
    final r7 = await room('7');
    await env.ensureDrawerStarted(counted: 500);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    // Signing in doesn't send a supervisor to the shift screen.
    expect(locationOf(app), Routes.home);

    await tapKey(tester, 'board.bed.7A');
    expect(find.byKey(const ValueKey('checkIn.noShift')), findsOneWidget);
    expect(find.text('Open your shift first'), findsOneWidget);
    expect(
      find.text('Check-ins and payments need an open shift.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('checkIn.guestSearch')), findsNothing);

    await tapKey(tester, 'checkIn.openShift');
    expect(locationOf(app), Routes.shift);
    // Back returns without opening one.
    await tapKey(tester, 'shift.back');
    expect(locationOf(app), Routes.checkIn);

    await tapKey(tester, 'checkIn.openShift');
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
    expect(text(tester, 'checkIn.bed'), '7 A');
    final shift = await ShiftRepository(
      env.db,
      env.audit,
    ).openShiftOnThisDevice();
    expect((shift!.userId, shift.openingFloat), (supervisor.id, 500));
  });

  testWidgets('no open shift: Back to beds', (tester) async {
    await room('7');
    await env.ensureDrawerStarted(counted: 500);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'board.bed.7A');
    await tapKey(tester, 'checkIn.backToBeds');
    expect(locationOf(app), Routes.home);
  });
}
