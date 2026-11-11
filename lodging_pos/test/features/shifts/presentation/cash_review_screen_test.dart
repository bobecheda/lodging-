import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/cash_reviews_repository.dart';
import 'package:lodging_pos/features/shifts/domain/cash_review.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late String maryShift;
  late String graceShift;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 11, 16, 8));
    supervisor = await env.createFirstSupervisor(testSetup);
    final mary = await env.addReceptionist('mary');
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
    // Mary closes short (needs review); then the supervisor's own shift
    // closes short too.
    maryShift = (await env.openShift(mary, startingCash: 2000)).id;
    env.clock.set(nairobiInstant(2026, 11, 16, 9));
    await env.checkIn(room.beds.single.id, by: mary);
    env.clock.set(nairobiInstant(2026, 11, 16, 20));
    await env.closeShiftWith(
      mary,
      maryShift,
      firstCount: 2600,
      reason: 'Change',
    );
    env.clock.set(nairobiInstant(2026, 11, 17, 8));
    graceShift = (await env.openShift(supervisor)).id;
    env.clock.set(nairobiInstant(2026, 11, 17, 9));
    await env.closeShiftWith(
      supervisor,
      graceShift,
      firstCount: 0,
      reason: 'x',
    );
    env.clock.set(nairobiInstant(2026, 11, 17, 10));
  });
  tearDown(() => env.close());

  testWidgets('the supervisor approves Mary’s close on Cash; their own close '
      'says the owner decides', (tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'nav.${Routes.cash}');
    expect(
      find.byKey(ValueKey('review.blocked.shift.$graceShift')),
      findsOneWidget,
    );
    expect(
      find.text('You’re named in this, so someone else decides.'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(ValueKey('review.approve.shift.$maryShift')),
    );
    await tapKey(tester, 'review.approve.shift.$maryShift');
    expect(
      find.byKey(ValueKey('review.decided.shift.$maryShift')),
      findsOneWidget,
    );
    expect(find.text('Approved by Grace Supervisor'), findsOneWidget);
    expect(await env.auditFor('shift.review_approve'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the owner rejects the supervisor’s close with a reason; it '
      'shows on the owner’s Today', (tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'nav.${Routes.cash}');
    await tapKey(tester, 'review.reject.shift.$graceShift');
    await tapKey(tester, 'review.reason.reject');
    expect(find.text('Say why you reject it.'), findsOneWidget);
    await enterKey(tester, 'review.reason', 'Count it with me tomorrow');
    await tapKey(tester, 'review.reason.reject');
    expect(
      find.text('Rejected by Amina Owner: Count it with me tomorrow'),
      findsOneWidget,
    );
    await tapKey(tester, 'nav.${Routes.today}');
    expect(
      find.byKey(ValueKey('today.attention.rejected.$graceShift')),
      findsOneWidget,
    );
    expect(find.text('Cash review rejected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a receptionist never sees a review: no Cash, no Today, no '
      'review on any screen they reach', (tester) async {
    // A rejection exists (before the app runs).
    final owner = env.owner!;
    await CashReviewsRepository(env.db, env.audit).decide(
      owner,
      ReviewTargetKind.shift,
      graceShift,
      approve: false,
      reason: 'Count it with me tomorrow',
    );
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'mary', 'desk-pass');
    await tapKey(tester, 'shift.submit');
    for (final route in [Routes.cash, Routes.today, Routes.shifts]) {
      app.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(locationOf(app), Routes.home, reason: route);
    }
    for (final route in [Routes.home, Routes.receipts, Routes.guests]) {
      app.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(find.textContaining('review'), findsNothing, reason: route);
      expect(find.textContaining('Count it with me'), findsNothing);
    }
  });
}
