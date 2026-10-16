import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/app.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/shell/desk_shell.dart';
import 'package:lodging_pos/core/auth/permissions.dart';

import '../../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  /// The app with a setup item that needs a permission.
  Future<void> pumpWithSetupItem(WidgetTester tester) async {
    tester.view
      ..physicalSize = deskSize
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = ProviderContainer(
      overrides: [
        ...env.overrides,
        deskNavItemsProvider.overrideWithValue(const [
          NavItem(
            route: Routes.home,
            label: 'Bed board',
            icon: Icons.grid_view,
          ),
          NavItem(
            route: '/admin/rooms',
            label: 'Rooms & beds',
            icon: Icons.bed_outlined,
            permissions: {Permission.manageRooms},
            setup: true,
          ),
        ]),
      ],
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: app, child: const App()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the owner sees SETUP · OWNER ONLY', (tester) async {
    await env.users.createFirstAdmin(testSetup);
    await pumpWithSetupItem(tester);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(find.text('SETUP · OWNER ONLY'), findsOneWidget);
    expect(find.text('Rooms & beds'), findsOneWidget);
  });

  testWidgets('a receptionist never sees the owner-only group', (tester) async {
    await env.users.createFirstAdmin(testSetup);
    await env.addReceptionist('desk');
    await pumpWithSetupItem(tester);
    await signInAs(tester, 'desk', 'desk-pass');
    await enterKey(tester, 'shift.float', '500');
    await tapKey(tester, 'shift.submit');
    expect(find.text('Bed board'), findsWidgets);
    expect(find.text('SETUP · OWNER ONLY'), findsNothing);
    expect(find.text('Rooms & beds'), findsNothing);
  });

  testWidgets('only screens that exist are listed', (tester) async {
    await env.users.createFirstAdmin(testSetup);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(app.read(deskNavItemsProvider).map((i) => i.route), [
      Routes.home,
      Routes.adminRooms,
      Routes.adminPrices,
      Routes.adminStaff,
    ]);
    expect(find.text('SETUP · OWNER ONLY'), findsOneWidget);
  });

  testWidgets('sync pill: not set up yet, counting changes waiting', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    final unsent = await env.db.select(env.db.outbox).get();
    expect(unsent, isNotEmpty);
    expect(
      find.text('Sync not set up · ${unsent.length} changes waiting'),
      findsOneWidget,
    );
  });

  testWidgets('the sidebar shows the lodging name', (tester) async {
    await env.users.createFirstAdmin(testSetup);
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(find.text('Sunrise Lodge'), findsOneWidget);
    expect(find.text('Front desk'), findsOneWidget);
  });
}
