import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 11, 16, 8));
    final supervisor = await env.createFirstSupervisor(testSetup);
    final mary = await env.addReceptionist('mary');
    // Starting cash 2,000; Mary's shift; KES 700 cash at 09:00: the drawer
    // should hold 2,700.
    await env.openShift(mary, startingCash: 2000);
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '4',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    env.clock.set(nairobiInstant(2026, 11, 16, 9));
    await env.checkIn(room.beds.single.id, by: mary);
    env.clock.set(nairobiInstant(2026, 11, 16, 12));
  });
  tearDown(() => env.close());

  /// No amount on screen: the "KES" label of an input is fine, a figure is
  /// not ("KES 2,700"), nor the drawer's expected 2,700 or its gap.
  void expectNoFigure(WidgetTester tester, String step) {
    expect(
      find.textContaining(RegExp(r'KES\s?\d')),
      findsNothing,
      reason: step,
    );
    for (final figure in ['2,700', '2700', 'Short', 'Over', 'short', 'over']) {
      expect(
        find.textContaining(figure),
        findsNothing,
        reason: '$step $figure',
      );
    }
  }

  testWidgets('a check with Mary present: she co-signs (a wrong password is '
      'refused and audited); the count is blind, one recount, a reason; it '
      'ends on "Counted." and no figure ever shows', (tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'nav.${Routes.cash}');
    await tapKey(tester, 'cash.check');
    expect(find.byKey(const ValueKey('drawer.present')), findsOneWidget);
    expectNoFigure(tester, 'co-sign');

    await enterKey(tester, 'drawer.password', 'not-hers');
    await tapKey(tester, 'drawer.cosign');
    expect(find.text('That password isn’t right.'), findsOneWidget);
    expectNoFigure(tester, 'refused co-sign');
    expect(await env.auditFor('drawer.cosign_failed'), hasLength(1));

    await enterKey(tester, 'drawer.password', 'desk-pass');
    await tapKey(tester, 'drawer.cosign');
    expect(find.byKey(const ValueKey('drawer.count')), findsOneWidget);
    expectNoFigure(tester, 'count');

    await enterKey(tester, 'drawer.count', '2600');
    await tapKey(tester, 'drawer.submit');
    expect(find.byKey(const ValueKey('drawer.countAgain')), findsOneWidget);
    expectNoFigure(tester, 'recount');

    await enterKey(tester, 'drawer.count', '2650');
    await tapKey(tester, 'drawer.submit');
    expect(find.byKey(const ValueKey('drawer.reasonNeeded')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer.count')), findsNothing);
    expectNoFigure(tester, 'reason');
    await enterKey(
      tester,
      'drawer.reason',
      'A guest was given too much change',
    );
    await tapKey(tester, 'drawer.reasonSave');

    expect(find.text('Counted.'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer.showWeek')), findsNothing);
    expectNoFigure(tester, 'done');

    final row = (await env.db.select(env.db.drawerEvents).get()).last;
    expect(
      (row.kind, row.firstCount, row.counted, row.needsReview),
      ('check', 2600, 2650, true),
    );
    expect(await env.auditFor('drawer.check'), hasLength(1));

    // The supervisor sees it in the chain, needing review.
    await tapKey(tester, 'drawer.back');
    expect(find.byKey(ValueKey('cash.check.${row.id}')), findsOneWidget);
    expect(find.text('Needs review.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a collection: counted, then taken away; "Counted." and the '
      'week’s figures only behind the button', (tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'nav.${Routes.cash}');
    await tapKey(tester, 'cash.collect');
    await enterKey(tester, 'drawer.password', 'desk-pass');
    await tapKey(tester, 'drawer.cosign');
    await enterKey(tester, 'drawer.count', '2,700');
    await tapKey(tester, 'drawer.submit');
    expect(find.byKey(const ValueKey('drawer.removed')), findsOneWidget);
    expectNoFigure(tester, 'taken away');

    await enterKey(tester, 'drawer.removed', '2,701');
    await tapKey(tester, 'drawer.removedSave');
    expect(
      find.text('You can’t take away more than you counted.'),
      findsOneWidget,
    );
    await enterKey(tester, 'drawer.removed', '2,500');
    await tapKey(tester, 'drawer.removedSave');
    expect(find.text('Counted.'), findsOneWidget);
    expectNoFigure(tester, 'done');
    expect(await env.auditFor('drawer.collect'), hasLength(1));

    await tapKey(tester, 'drawer.showWeek');
    expect(find.byKey(const ValueKey('drawer.week')), findsOneWidget);
    expect(find.text('KES 2,700'), findsWidgets);
    expect(find.text('KES 200'), findsOneWidget); // left in the drawer
    expect(tester.takeException(), isNull);
  });

  testWidgets('a receptionist has no way in', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'mary', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    for (final route in [
      Routes.cash,
      Routes.drawerCountFor('check'),
      Routes.drawerCountFor('collect'),
    ]) {
      app.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(locationOf(app), Routes.home, reason: route);
    }
  });
}
