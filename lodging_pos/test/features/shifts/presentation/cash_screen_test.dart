import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() async {
    env = TestEnv();
    await env.createFirstSupervisor(testSetup);
    await env.addReceptionist('mary');
  });
  tearDown(() => env.close());

  testWidgets('the first day: the receptionist can’t open a shift until the '
      'starting cash is counted, and never types a float', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'mary', 'desk-pass');
    expect(locationOf(app), Routes.shift);
    expect(find.byKey(const ValueKey('shift.float')), findsNothing);
    expect(find.byKey(const ValueKey('shift.noStartingCash')), findsOneWidget);
    expect(find.byKey(const ValueKey('shift.countStart')), findsNothing);
    await tapKey(tester, 'shift.submit'); // disabled
    expect(await env.db.select(env.db.shifts).get(), isEmpty);
  });

  testWidgets('the supervisor counts the starting cash on Cash, once; then '
      'the chain starts with it', (tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'nav.${Routes.cash}');
    expect(find.text('Not counted yet'), findsOneWidget);
    await tapKey(tester, 'cash.startSave');
    expect(find.text('Enter the cash you counted.'), findsOneWidget);
    await enterKey(tester, 'cash.startCount', '2,000');
    await tapKey(tester, 'cash.startSave');
    expect(find.byKey(const ValueKey('cash.startCard')), findsNothing);
    expect(find.byKey(const ValueKey('cash.start')), findsOneWidget);
    expect(find.text('KES 2,000'), findsOneWidget);
    final start = await env.db.select(env.db.drawerEvents).getSingle();
    expect((start.kind, start.counted), ('start', 2000));
    expect(await env.auditFor('drawer.start'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
