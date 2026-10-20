import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount desk;
  late RoomSummary r5;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19)); // Thu 19:00
    owner = await env.users.createFirstAdmin(testSetup);
    desk = await env.addReceptionist('desk');
    r5 = await RoomsRepository(env.db, env.audit).createRoom(
      owner,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe, // 700
        bedBCategoryId: null,
      ),
    );
  });
  tearDown(() => env.close());

  /// Desk signed in with her shift (opened by the check-in), on the board.
  Future<ProviderContainer> deskOnBoard(WidgetTester tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    expect(locationOf(app), Routes.home);
    return app;
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  Finder stepperValue() => find.byKey(const ValueKey('stepper.value'));

  String buttonLabel(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('panel.checkOut')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  testWidgets('on time: the panel, a confirmation (Cancel changes nothing), '
      'then checked out and the bed needs cleaning', (tester) async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 9)); // Fri 09:00
    await deskOnBoard(tester);

    await tapKey(tester, 'board.bed.5A');
    expect(text(tester, 'panel.title'), 'Room 5 · Bed A');
    expect(find.text('Test Guest'), findsWidgets);
    expect(find.textContaining('0700 ••• 000'), findsOneWidget);
    expect(find.text('R-000001'), findsOneWidget);
    expect(buttonLabel(tester), 'Check out');

    await tapKey(tester, 'panel.checkOut');
    expect(
      find.text(
        'Check out Test Guest from Room 5, Bed A? The bed will need '
        'cleaning.',
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'panel.confirm.cancel');
    expect((await env.checkOuts.stay(stayId)).isActive, isTrue);

    await tapKey(tester, 'panel.checkOut');
    await tapKey(tester, 'panel.confirm.ok');
    expect(text(tester, 'panel.result.title'), 'Checked out at 09:00');
    expect((await env.checkOuts.stay(stayId)).isActive, isFalse);

    await tapKey(tester, 'panel.done');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board.bed.5A')),
        matching: find.text('TO CLEAN'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('early: the refund figures, the amount in the confirmation, '
      'then the request waiting for approval and the saved phone', (
    tester,
  ) async {
    await env.checkIn(r5.beds.single.id, by: desk, nights: 3);
    // Fri 10:30: night 1 used (grace), 2 back.
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 30));
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.5A');

    expect(text(tester, 'panel.refund'), 'KES 1,400');
    expect(buttonLabel(tester), 'Check out and request refund of KES 1,400');
    await tapKey(tester, 'panel.checkOut');
    expect(
      find.text(
        'Check out Test Guest from Room 5, Bed A? A refund of KES 1,400 will '
        'be requested for the owner’s approval. The bed will need cleaning.',
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'panel.confirm.ok');

    expect(find.text('WAITING FOR OWNER APPROVAL'), findsOneWidget);
    expect(
      text(tester, 'panel.result.refund'),
      'Refund of KES 1,400 requested (2 × KES 700).',
    );
    expect(
      text(tester, 'panel.result.phone'),
      'The guest’s phone 0700 ••• 000 is saved for the refund.',
    );
    final refund = await env.db.select(env.db.refunds).getSingle();
    expect(refund.amount, 1400);
  });

  testWidgets('late: from the overstay bar; the payment is required; then '
      'the late receipt with Print', (tester) async {
    await env.checkIn(r5.beds.single.id, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 11, 30)); // 30 min past grace
    await deskOnBoard(tester);

    await tapKey(tester, 'board.overstay.checkOut');
    expect(find.text('OVERSTAY · 30 min past grace'), findsOneWidget);
    expect(text(tester, 'panel.lateTotal'), 'KES 700');
    expect(buttonLabel(tester), 'Charge 1 night and check out');

    await tapKey(tester, 'panel.checkOut'); // no method yet, no dialog
    expect(find.text('Choose how they paid.'), findsOneWidget);
    expect(find.byKey(const ValueKey('panel.confirm')), findsNothing);

    await tapKeyIn(tester, 'panel.method', 'choice.PaymentMethod.cash');
    await tapKey(tester, 'panel.checkOut');
    expect(text(tester, 'panel.result.title'), 'Checked out at 11:30');
    expect(find.byKey(const ValueKey('receipt.view')), findsOneWidget);
    expect(find.text('Late checkout'), findsOneWidget);
    expect(text(tester, 'receipt.number'), 'R-000002');
    await tapKey(tester, 'receipt.print');
    expect(env.receiptOutput.printed, ['R-000002.pdf']);
  });

  testWidgets('opened within grace, confirmed after: refused, and nothing '
      'is saved', (tester) async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 58));
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.5A');
    expect(buttonLabel(tester), 'Check out');

    env.clock.set(nairobiInstant(2026, 10, 16, 11, 1));
    await tapKey(tester, 'panel.checkOut');
    await tapKey(tester, 'panel.confirm.ok');
    expect(
      find.text(
        'It’s now past 11:00, so 1 night is charged. Check and confirm '
        'again.',
      ),
      findsOneWidget,
    );
    expect((await env.checkOuts.stay(stayId)).isActive, isTrue);
  });

  testWidgets('an admin without a shift: the note, then Open shift and back '
      'to the same panel, ready to check out', (tester) async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk);
    // Desk closes her shift (FD-11), so the device has no open shift.
    final shifts = ShiftRepository(env.db, env.audit);
    final shift = (await shifts.openShiftOnThisDevice())!;
    await shifts.closeShift(
      desk,
      shift.id,
      firstCount: 700,
      counted: 700,
      note: '',
      shown: await shifts.takings(shift.id),
    );
    env.clock.set(nairobiInstant(2026, 10, 16, 9));
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(locationOf(app), Routes.home); // never forced to the shift screen

    await tapKey(tester, 'board.bed.5A');
    expect(find.byKey(const ValueKey('panel.noShift')), findsOneWidget);
    await tapKey(tester, 'panel.openShift');
    expect(locationOf(app), Routes.shift);
    await enterKey(tester, 'shift.float', '0');
    await tapKey(tester, 'shift.submit');

    // Back on the board with the same panel open, now without the note.
    expect(text(tester, 'panel.title'), 'Room 5 · Bed A');
    expect(find.byKey(const ValueKey('panel.noShift')), findsNothing);
    await tapKey(tester, 'panel.checkOut');
    await tapKey(tester, 'panel.confirm.ok');
    expect((await env.checkOuts.stay(stayId)).isActive, isFalse);
  });

  testWidgets('a receptionist’s shift on the device: an admin sees the note, '
      'opens nothing, Back returns to the panel', (tester) async {
    await env.checkIn(r5.beds.single.id, by: desk); // desk's shift is open
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'board.bed.5A');
    expect(
      find.text('Checkout records money. Open a shift first.'),
      findsOneWidget,
    );
    final button = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(const ValueKey('panel.checkOut')),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tapKey(tester, 'panel.openShift');
    expect(locationOf(app), Routes.shift);
    // Desk's shift blocks a second one; Back goes back to the panel.
    expect(find.textContaining("shift must be closed first"), findsOneWidget);
    await tapKey(tester, 'shift.back');
    expect(locationOf(app), Routes.home);
    expect(text(tester, 'panel.title'), 'Room 5 · Bed A');
  });

  group('Extend (FD-7)', () {
    Finder extendButton() => find.descendant(
      of: find.byKey(const ValueKey('extend.save')),
      matching: find.byType(TextButton),
    );

    testWidgets('within paid time: Extend comes before Check out; the '
        'payment is required; then the extension receipt with Print', (
      tester,
    ) async {
      final stayId = await env.checkIn(r5.beds.single.id, by: desk);
      env.clock.set(nairobiInstant(2026, 10, 16, 8)); // Fri 08:00
      await deskOnBoard(tester);
      await tapKey(tester, 'board.bed.5A');

      expect(
        tester.getTopLeft(find.text('EXTEND STAY')).dy,
        lessThan(tester.getTopLeft(find.text('CHECK OUT')).dy),
      );
      expect(find.byKey(const ValueKey('extend.minReason')), findsNothing);
      expect(
        find.textContaining('Sat 17 Oct, 10:00', findRichText: true),
        findsOneWidget,
      );
      expect(text(tester, 'extend.total'), 'KES 700');
      await tapKey(tester, 'stepper.plus');
      expect(text(tester, 'extend.total'), 'KES 1,400');
      expect(find.text('2 × KES 700 (check-in price)'), findsOneWidget);

      await tapKey(tester, 'extend.save'); // no method yet
      expect(text(tester, 'extend.paymentError'), 'Choose how they paid.');
      expect((await env.checkOuts.stay(stayId)).charges, hasLength(1));

      await tapKeyIn(tester, 'extend.method', 'choice.PaymentMethod.cash');
      await tapKey(tester, 'extend.save');
      expect(text(tester, 'extend.result.title'), 'Extended by 2 nights');
      expect(
        text(tester, 'extend.result.checkout'),
        'New checkout Sun 18 Oct, 10:00.',
      );
      expect(text(tester, 'receipt.number'), 'R-000002');
      expect(find.text('Extension · 2 nights'), findsOneWidget);
      await tapKey(tester, 'receipt.print');
      expect(env.receiptOutput.printed, ['R-000002.pdf']);

      await tapKey(tester, 'extend.done');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('board.bed.5A')),
          matching: find.textContaining('until Sun 10:00'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('from the overstay bar: at least the nights already started, '
        'with the reason; fewer is refused; then no longer an overstay', (
      tester,
    ) async {
      await env.checkIn(r5.beds.single.id, by: desk); // paid to Fri 10:00
      env.clock.set(nairobiInstant(2026, 10, 18, 12)); // Sun 12:00: 3 started
      await deskOnBoard(tester);

      await tapKey(tester, 'board.overstay.extend');
      expect(
        text(tester, 'extend.minReason'),
        'At least 3 nights: 3 have started since Fri 10:00.',
      );
      expect(tester.widget<TextField>(stepperValue()).controller!.text, '3');
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('stepper.minus')))
            .onPressed,
        isNull,
      );
      expect(text(tester, 'extend.total'), 'KES 2,100');

      await enterKey(tester, 'stepper.value', '2');
      await tester.pumpAndSettle();
      expect(
        text(tester, 'extend.nightsError'),
        'At least 3 nights: that many have already started.',
      );
      expect(tester.widget<TextButton>(extendButton()).onPressed, isNull);

      await enterKey(tester, 'stepper.value', '4');
      await tester.pumpAndSettle();
      await tapKeyIn(tester, 'extend.method', 'choice.PaymentMethod.paybill');
      await enterKey(tester, 'extend.mpesaCode', 'QJK7H2LM4P');
      await tapKey(tester, 'extend.save');
      expect(text(tester, 'extend.result.title'), 'Extended by 4 nights');
      expect(
        text(tester, 'extend.result.checkout'),
        'New checkout Tue 20 Oct, 10:00.',
      );
      await tapKey(tester, 'extend.done');
      expect(find.byKey(const ValueKey('board.overstayBar')), findsNothing);
    });

    testWidgets('an admin without a shift of their own: the note, and '
        'Extend is disabled', (tester) async {
      await env.checkIn(r5.beds.single.id, by: desk); // desk's shift is open
      await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'board.bed.5A');
      expect(find.byKey(const ValueKey('panel.noShift')), findsOneWidget);
      expect(find.byKey(const ValueKey('extend.card')), findsOneWidget);
      expect(tester.widget<TextButton>(extendButton()).onPressed, isNull);
    });
  });
}
