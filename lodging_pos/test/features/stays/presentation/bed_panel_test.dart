import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/widgets/bed_status_tile.dart';
import 'package:lodging_pos/app/widgets/buttons.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/stays/presentation/bed_panel.dart';

import '../../../helpers/fixtures.dart';

/// The bed panel, v2 (PR 5, Figma "Bed panel · states"): Occupied, Check out
/// (early, on time), Extend and the late checkout during an overstay, and
/// Void stay for the supervisor.
void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount desk;
  late RoomSummary r5;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19)); // Thu 19:00
    supervisor = await env.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('desk');
    r5 = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
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

  AppButton button(WidgetTester tester, String key) =>
      tester.widget<AppButton>(find.byKey(ValueKey(key)));

  BedTileStatus tile(WidgetTester tester) => tester
      .widget<BedStatusTile>(find.byKey(const ValueKey('board.bed.5A')))
      .status;

  testWidgets('occupied: the guest, the stay and its receipts; Check out '
      'shows what leaving means, Back changes nothing; then checked out and '
      'the bed needs cleaning', (tester) async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 9)); // Fri 09:00
    await deskOnBoard(tester);

    await tapKey(tester, 'board.bed.5A');
    expect(text(tester, 'panel.title'), '5 A');
    expect(find.text('Deluxe · KES 700 a night'), findsOneWidget);
    expect(find.text('Occupied'), findsWidgets);
    expect(find.text('Test Guest'), findsOneWidget);
    expect(find.text('0700 ••• 000'), findsOneWidget);
    expect(find.text('Fri 16 Oct, 10:00'), findsOneWidget); // paid until
    expect(find.text('1 × KES 700'), findsOneWidget);
    expect(find.text('R-000001 · Cash'), findsOneWidget);
    // The receptionist can't void.
    expect(find.byKey(const ValueKey('panel.void')), findsNothing);

    await tapKey(tester, 'panel.toCheckOut');
    expect(button(tester, 'panel.checkOut').label, 'Check out');
    await tapKey(tester, 'panel.back');
    expect(find.byKey(const ValueKey('panel.toCheckOut')), findsOneWidget);
    expect((await env.checkOuts.stay(stayId)).isActive, isTrue);

    await tapKey(tester, 'panel.toCheckOut');
    await tapKey(tester, 'panel.checkOut');
    expect(text(tester, 'panel.result.title'), 'Checked out at 09:00');
    expect((await env.checkOuts.stay(stayId)).isActive, isFalse);

    await tapKey(tester, 'panel.done');
    expect(tile(tester), BedTileStatus.toClean);
  });

  testWidgets('early: the refund card, the amount on the button, then the '
      'request waiting for approval and the saved phone', (tester) async {
    await env.checkIn(r5.beds.single.id, by: desk, nights: 3);
    // Fri 10:30: night 1 used (grace), 2 back.
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 30));
    await deskOnBoard(tester);
    await tapKey(tester, 'board.bed.5A');
    await tapKey(tester, 'panel.toCheckOut');

    expect(text(tester, 'panel.refund'), 'KES 1,400');
    expect(find.text('Refund · 2 × KES 700'), findsOneWidget);
    expect(find.text('Needs approval before it is paid'), findsOneWidget);
    expect(
      button(tester, 'panel.checkOut').label,
      'Check out and request KES 1,400',
    );
    await tapKey(tester, 'panel.checkOut');

    expect(find.text('Waiting for owner approval'), findsOneWidget);
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

  testWidgets('overstay: the panel opens on Extend with the red banner; '
      '"Charge 1 night and check out" needs the payment, then the late '
      'receipt with Print', (tester) async {
    await env.checkIn(r5.beds.single.id, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 11, 30)); // 30 min past grace
    await deskOnBoard(tester);

    await tapKey(tester, 'board.overstay.5A');
    expect(find.text('Overstay'), findsWidgets);
    expect(find.text('1 h past 10:00 · paid to Fri 16 Oct'), findsOneWidget);
    expect(
      button(tester, 'panel.checkOut').label,
      'Charge 1 night and check out',
    );

    await tapKey(tester, 'panel.checkOut'); // no method yet
    expect(text(tester, 'panel.paymentError'), 'Choose Cash or M-Pesa.');

    await tapKeyIn(tester, 'extend.method', 'choice.PaymentMethod.cash');
    expect(text(tester, 'panel.lateTotal'), 'KES 700');
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
    await tapKey(tester, 'panel.toCheckOut');
    expect(button(tester, 'panel.checkOut').label, 'Check out');

    env.clock.set(nairobiInstant(2026, 10, 16, 11, 1));
    await tapKey(tester, 'panel.checkOut');
    expect(
      find.text(
        'It’s now past 11:00, so 1 night is charged. Check and confirm '
        'again.',
      ),
      findsOneWidget,
    );
    expect((await env.checkOuts.stay(stayId)).isActive, isTrue);
  });

  testWidgets(
    'a supervisor without a shift: the note, then Open shift and back '
    'to the same panel, ready to check out',
    (tester) async {
      final stayId = await env.checkIn(r5.beds.single.id, by: desk);
      // Desk closes her shift (FD-11), so the device has no open shift.
      final shifts = ShiftRepository(env.db, env.audit);
      final shift = (await shifts.openShiftOnThisDevice())!;
      await env.closeShiftWith(desk, shift.id, firstCount: 700);
      env.clock.set(nairobiInstant(2026, 10, 16, 9));
      await env.ensureDrawerStarted(counted: 0);
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      expect(locationOf(app), Routes.home); // never forced to the shift screen

      await tapKey(tester, 'board.bed.5A');
      await tapKey(tester, 'panel.toCheckOut');
      expect(find.byKey(const ValueKey('panel.noShift')), findsOneWidget);
      expect(button(tester, 'panel.checkOut').onPressed, isNull);
      await tapKey(tester, 'panel.openShift');
      expect(locationOf(app), Routes.shift);
      await tapKey(tester, 'shift.submit');

      // Back on the board with the same panel open.
      expect(text(tester, 'panel.title'), '5 A');
      await tapKey(tester, 'panel.toCheckOut');
      expect(find.byKey(const ValueKey('panel.noShift')), findsNothing);
      await tapKey(tester, 'panel.checkOut');
      expect((await env.checkOuts.stay(stayId)).isActive, isFalse);
    },
  );

  testWidgets(
    'a receptionist’s shift on the device: a supervisor sees the note, '
    'opens nothing, Back returns to the panel',
    (tester) async {
      await env.checkIn(r5.beds.single.id, by: desk); // desk's shift is open
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'board.bed.5A');
      await tapKey(tester, 'panel.toCheckOut');
      expect(
        find.text('This records money. Open a shift first.'),
        findsOneWidget,
      );
      expect(button(tester, 'panel.checkOut').onPressed, isNull);

      await tapKey(tester, 'panel.openShift');
      expect(locationOf(app), Routes.shift);
      // Desk's shift blocks a second one; Back goes back to the panel.
      expect(find.textContaining('shift must be closed first'), findsOneWidget);
      await tapKey(tester, 'shift.back');
      expect(locationOf(app), Routes.home);
      expect(text(tester, 'panel.title'), '5 A');
    },
  );

  group('Extend (FD-7)', () {
    testWidgets('within paid time: Extend stay beside Check out; the '
        'payment is required; then the extension receipt with Print', (
      tester,
    ) async {
      final stayId = await env.checkIn(r5.beds.single.id, by: desk);
      env.clock.set(nairobiInstant(2026, 10, 16, 8)); // Fri 08:00
      await deskOnBoard(tester);
      await tapKey(tester, 'board.bed.5A');

      expect(
        tester.getTopLeft(find.byKey(const ValueKey('panel.extend'))).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('panel.toCheckOut'))).dx,
        ),
      );
      await tapKey(tester, 'panel.extend');
      expect(find.byKey(const ValueKey('extend.minReason')), findsNothing);
      expect(text(tester, 'extend.newCheckout'), 'Out Sat 17 Oct, 10:00');
      expect(find.text('KES 700 (check-in price)'), findsOneWidget);
      await tapKey(tester, 'stepper.plus');
      expect(text(tester, 'extend.newCheckout'), 'Out Sun 18 Oct, 10:00');

      // No method yet: the line says so and Extend waits.
      expect(text(tester, 'panel.confirmLine'), 'Choose Cash or M-Pesa');
      expect(button(tester, 'extend.save').onPressed, isNull);
      expect((await env.checkOuts.stay(stayId)).charges, hasLength(1));

      await tapKeyIn(tester, 'extend.method', 'choice.PaymentMethod.cash');
      expect(text(tester, 'extend.total'), 'KES 1,400');
      expect(button(tester, 'extend.save').label, 'Extend and print receipt');
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
          matching: find.text('Guest · Sun'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('from the overstay card: at least the nights already '
        'started, with the reason; fewer is refused; then no longer an '
        'overstay', (tester) async {
      await env.checkIn(r5.beds.single.id, by: desk); // paid to Fri 10:00
      env.clock.set(nairobiInstant(2026, 10, 18, 12)); // Sun 12:00: 3 started
      await deskOnBoard(tester);

      await tapKey(tester, 'board.overstay.5A');
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
      await tapKeyIn(tester, 'extend.method', 'choice.PaymentMethod.paybill');
      expect(text(tester, 'extend.total'), 'KES 2,100');

      await enterKey(tester, 'stepper.value', '2');
      await tester.pumpAndSettle();
      expect(
        text(tester, 'extend.nightsError'),
        'At least 3 nights: that many have already started.',
      );
      expect(button(tester, 'extend.save').onPressed, isNull);

      await enterKey(tester, 'stepper.value', '4');
      await tester.pumpAndSettle();
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

    testWidgets('a supervisor without a shift of their own: the note, and '
        'Extend is disabled', (tester) async {
      await env.checkIn(r5.beds.single.id, by: desk); // desk's shift is open
      await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'board.bed.5A');
      await tapKey(tester, 'panel.extend');
      await tapKeyIn(tester, 'extend.method', 'choice.PaymentMethod.cash');
      expect(find.byKey(const ValueKey('panel.noShift')), findsOneWidget);
      expect(button(tester, 'extend.save').onPressed, isNull);
    });
  });

  group('Void stay (AD-7 in the bed panel, v2 PR 5)', () {
    testWidgets('the supervisor voids a stay someone else checked in: the '
        'receipts it voids, the bed after; a reason is required; then the '
        'bed needs cleaning', (tester) async {
      final stayId = await env.checkIn(r5.beds.single.id, by: desk);
      env.clock.set(nairobiInstant(2026, 10, 16, 9));
      await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'board.bed.5A');

      await tapKey(tester, 'panel.void');
      expect(find.text('Voids the stay and its payments'), findsOneWidget);
      expect(
        find.text('Checked in by ${desk.fullName} · Thu 15 Oct'),
        findsOneWidget,
      );
      expect(find.text('R-000001 · Cash'), findsOneWidget);
      expect(find.text('− KES 700'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BedPanel),
          matching: find.text('To clean'),
        ),
        findsOneWidget,
      );
      expect(button(tester, 'panel.voidConfirm').onPressed, isNull);

      await tapKey(tester, 'panel.voidCancel');
      expect(find.byKey(const ValueKey('panel.void')), findsOneWidget);
      await tapKey(tester, 'panel.void');
      await enterKey(tester, 'panel.voidReason', 'Checked into the wrong bed');
      await tester.pumpAndSettle();
      await tapKey(tester, 'panel.voidConfirm');
      expect(find.byKey(const ValueKey('panel.voided')), findsOneWidget);

      final voids = await env.db.select(env.db.voids).get();
      expect({for (final v in voids) v.targetType}, {'stay', 'payment'});
      expect((await env.checkOuts.stay(stayId)).isActive, isFalse);
      await tapKey(tester, 'panel.done');
      expect(tile(tester), BedTileStatus.toClean);
    });

    testWidgets('a stay the supervisor checked in themselves: the reason '
        'instead of the button (Story A rule)', (tester) async {
      await env.openShift(supervisor, startingCash: 0);
      await env.checkIn(r5.beds.single.id, by: supervisor);
      await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'board.bed.5A');
      await tapKey(tester, 'panel.void');
      expect(
        find.text(
          'You checked Room 5 · Bed A in yourself, so someone else must void '
          'it.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('panel.voidConfirm')), findsNothing);
      expect(find.byKey(const ValueKey('panel.voidCancel')), findsOneWidget);
    });
  });
}
