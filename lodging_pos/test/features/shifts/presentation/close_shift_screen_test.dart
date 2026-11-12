import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount mary;
  late String shiftId;

  setUp(() async {
    env = TestEnv();
    supervisor = await env.createFirstSupervisor(testSetup);
    mary = await env.addReceptionist('mary');
    await env.addReceptionist('tom');
    // Mary: float KES 1,000, then KES 700 in cash → expected KES 1,700.
    shiftId = (await env.openShift(mary, startingCash: 1000)).id;
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
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
    await tapKey(tester, 'closeShift.submit');
  }

  /// Nothing on screen gives away what the drawer should hold: no expected
  /// figure, no short or over (Story B: the receptionist's close is blind).
  void expectNothingGivenAway(WidgetTester tester) {
    expect(find.textContaining('1,700'), findsNothing);
    expect(find.textContaining('1,000'), findsNothing);
    expect(find.textContaining('Expected'), findsNothing);
    for (final word in ['short', 'Short', 'SHORT', 'over', 'Over', 'OVER']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
    expect(find.byKey(const ValueKey('closeShift.variance')), findsNothing);
  }

  testWidgets('blind: a count that doesn’t match says only that; leaving '
      'and coming back resumes at the recount; a recount that still doesn’t '
      'match needs a reason; the shift closes for review; no figure ever '
      'shows', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'mary', 'desk-pass');
    // The resume card has no figures either.
    expect(find.byKey(const ValueKey('shift.takenTotal')), findsNothing);
    expectNothingGivenAway(tester);
    await tapKey(tester, 'shift.continue');

    await tapKey(tester, 'shell.closeShift');
    expect(locationOf(app), Routes.closeShift);
    expectNothingGivenAway(tester);

    await count(tester, '1500');
    expect(find.byKey(const ValueKey('closeShift.countAgain')), findsOneWidget);
    expectNothingGivenAway(tester);

    // Leave and come back: still the recount, never a new first count.
    await tapKey(tester, 'nav.${Routes.home}');
    await tapKey(tester, 'shell.closeShift');
    expect(find.byKey(const ValueKey('closeShift.countAgain')), findsOneWidget);

    await count(tester, '1600');
    expect(
      find.byKey(const ValueKey('closeShift.reasonNeeded')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('closeShift.count')), findsNothing);
    expectNothingGivenAway(tester);
    await tapKey(tester, 'closeShift.confirm');
    expect(find.text('Say why the count may be different.'), findsOneWidget);
    await enterKey(tester, 'closeShift.reason', 'Gave change from my pocket');
    await tapKey(tester, 'closeShift.confirm');
    expect(find.byKey(const ValueKey('closeShift.done')), findsOneWidget);
    expect(
      find.text('Your count and your reason are recorded for review.'),
      findsOneWidget,
    );
    expectNothingGivenAway(tester);

    final shift = await (env.db.select(
      env.db.shifts,
    )..where((s) => s.id.equals(shiftId))).getSingle();
    expect((shift.firstCount, shift.countedCash), (1500, 1600));
    expect((shift.variance, shift.needsReview), (-100, true));
    expect(shift.closeNote, 'Gave change from my pocket');

    await tapKey(tester, 'closeShift.signOut');
    expect(locationOf(app), Routes.login);
    // The next receptionist opens a shift without typing a float.
    await signInAs(tester, 'tom', 'desk-pass');
    expect(locationOf(app), Routes.shift);
    expect(find.byKey(const ValueKey('shift.float')), findsNothing);
    await tapKey(tester, 'shift.submit');
    expect(locationOf(app), Routes.home);
    expect((await env.db.select(env.db.shifts).get()).last.openingFloat, 1600);
  });

  testWidgets('a count that matches closes at once: "Your count is '
      'recorded", nothing more', (tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'mary', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    await tapKey(tester, 'shell.closeShift');
    await count(tester, '1,700');
    expect(find.text('Your count is recorded.'), findsOneWidget);
    expect(find.textContaining('Expected'), findsNothing);
  });

  testWidgets('a blocked receptionist is told who can close the shift', (
    tester,
  ) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'tom', 'desk-pass');
    expect(
      text(tester, 'shift.askToClose'),
      "Ask Desk to sign in and close it, or ask the supervisor to close Desk's "
      'shift.',
    );
    expect(find.byKey(const ValueKey('shift.closeOther')), findsNothing);
  });

  testWidgets(
    'the supervisor closes Mary’s shift from Shifts, blind too; after the '
    'close they see the figures; the list says who closed it and that it '
    'matched only on recount',
    (tester) async {
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'nav.${Routes.shifts}');
      expect(find.text('Open'), findsOneWidget);
      await tapKey(tester, 'shifts.close.$shiftId');
      expect(text(tester, 'closeShift.whose'), startsWith('Desk MARY'));
      expect(find.textContaining('1,700'), findsNothing);

      await count(tester, '1800');
      expect(
        find.byKey(const ValueKey('closeShift.countAgain')),
        findsOneWidget,
      );
      await count(tester, '1700');
      expect(text(tester, 'closeShift.variance'), 'Exact');
      await tapKey(tester, 'closeShift.backToShifts');
      expect(locationOf(app), Routes.shifts);

      expect(text(tester, 'shifts.variance.$shiftId'), 'Exact');
      expect(find.byKey(ValueKey('shifts.onRecount.$shiftId')), findsOneWidget);
      expect(
        text(tester, 'shifts.closedBy.$shiftId'),
        'closed by Grace Supervisor for Desk MARY’s shift',
      );
      // Mary's shift no longer blocks the device.
      expect(find.text('Open'), findsNothing);
    },
  );

  testWidgets('the owner reaching the blocked card can close it there', (
    tester,
  ) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    app.read(routerProvider).go(Routes.shiftThen(Routes.home));
    await tester.pumpAndSettle();
    await tapKey(tester, 'shift.closeOther');
    expect(locationOf(app), Routes.closeShift);
    expect(text(tester, 'closeShift.whose'), startsWith('Desk MARY'));
  });

  testWidgets('a receptionist can’t open Shifts or Cash', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'mary', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    for (final route in [Routes.shifts, Routes.cash]) {
      expect(find.byKey(ValueKey('nav.$route')), findsNothing);
      app.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(locationOf(app), Routes.home, reason: route);
    }
  });

  testWidgets('Cash: the supervisor sees what the drawer should hold and the '
      'chain', (tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'nav.${Routes.cash}');
    expect(text(tester, 'cash.now'), 'KES 1,700');
    expect(find.byKey(ValueKey('cash.open.$shiftId')), findsOneWidget);
    expect(find.byKey(const ValueKey('cash.start')), findsOneWidget);
    expect(find.byKey(const ValueKey('cash.startCard')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
