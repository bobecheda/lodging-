import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount mary;
  late String shiftId;

  setUp(() async {
    env = TestEnv();
    owner = await env.users.createFirstAdmin(testSetup);
    mary = await env.addReceptionist('mary');
    await env.addReceptionist('tom');
    // Mary: float KES 1,000, then KES 700 in cash → expected KES 1,700.
    shiftId = (await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: mary, openingFloat: 1000)).id;
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
    await env.checkIn(room.beds.single.id, by: mary);
  });
  tearDown(() => env.close());

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  Future<void> count(WidgetTester tester, String amount) async {
    await enterKey(tester, 'closeShift.count', amount);
    await tapKey(tester, 'closeShift.review');
  }

  testWidgets('blind count, a refused close, a recount, then close and '
      'sign out; the next receptionist is no longer blocked', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'mary', 'desk-pass');
    await tapKey(tester, 'shift.continue');

    await tapKey(tester, 'shell.closeShift');
    expect(locationOf(app), Routes.closeShift);
    // Blind: nothing about what's expected before the count.
    expect(find.byKey(const ValueKey('closeShift.expected')), findsNothing);
    expect(find.textContaining('1,700'), findsNothing);

    await count(tester, '1500');
    expect(text(tester, 'closeShift.expected'), 'KES 1,700');
    expect(text(tester, 'closeShift.counted'), 'KES 1,500');
    expect(find.text('SHORT KES 200'), findsOneWidget);
    await tapKey(tester, 'closeShift.confirm');
    expect(find.text('Say why the cash is short.'), findsOneWidget);

    await tapKey(tester, 'closeShift.recount');
    await count(tester, '1,700');
    expect(
      text(tester, 'closeShift.recountLine'),
      'first count KES 1,500 → recounted KES 1,700',
    );
    expect(find.text('EXACT'), findsOneWidget);
    await tapKey(tester, 'closeShift.confirm');
    expect(find.byKey(const ValueKey('closeShift.done')), findsOneWidget);

    final shift = await (env.db.select(
      env.db.shifts,
    )..where((s) => s.id.equals(shiftId))).getSingle();
    expect((shift.firstCount, shift.countedCash), (1500, 1700));
    expect((shift.variance, shift.closedBy), (0, mary.id));

    await tapKey(tester, 'closeShift.signOut');
    expect(locationOf(app), Routes.login);
    await signInAs(tester, 'tom', 'desk-pass');
    expect(locationOf(app), Routes.shift);
    expect(find.byKey(const ValueKey('shift.float')), findsOneWidget);
  });

  testWidgets('a blocked receptionist is told who can close the shift', (
    tester,
  ) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'tom', 'desk-pass');
    expect(
      text(tester, 'shift.askToClose'),
      "Ask Desk to sign in and close it, or ask the owner to close Desk's "
      'shift.',
    );
    expect(find.byKey(const ValueKey('shift.closeOther')), findsNothing);
  });

  testWidgets('the owner closes Mary’s shift from Shifts; the list says who '
      'closed it', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'nav.${Routes.shifts}');
    expect(find.text('OPEN'), findsOneWidget);
    await tapKey(tester, 'shifts.close.$shiftId');
    expect(text(tester, 'closeShift.whose'), startsWith('Desk MARY'));

    await count(tester, '1800');
    expect(find.text('OVER KES 100'), findsOneWidget);
    await enterKey(tester, 'closeShift.note', 'Guest left a tip in the till');
    await tapKey(tester, 'closeShift.confirm');
    await tapKey(tester, 'closeShift.backToShifts');
    expect(locationOf(app), Routes.shifts);

    expect(text(tester, 'shifts.variance.$shiftId'), 'Over KES 100');
    expect(
      text(tester, 'shifts.closedBy.$shiftId'),
      'closed by Grace Owner for Desk MARY’s shift',
    );
    expect(find.text('“Guest left a tip in the till”'), findsOneWidget);
    // Mary's shift no longer blocks the device.
    expect(find.text('OPEN'), findsNothing);
  });

  testWidgets('the owner reaching the blocked card can close it there', (
    tester,
  ) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    app.read(routerProvider).go(Routes.shiftThen(Routes.home));
    await tester.pumpAndSettle();
    await tapKey(tester, 'shift.closeOther');
    expect(locationOf(app), Routes.closeShift);
    expect(text(tester, 'closeShift.whose'), startsWith('Desk MARY'));
  });

  testWidgets('a receptionist can’t open the owner’s Shifts screen', (
    tester,
  ) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'mary', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    expect(find.byKey(const ValueKey('nav./shifts')), findsNothing);
    app.read(routerProvider).go(Routes.shifts);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.home);
  });
}
