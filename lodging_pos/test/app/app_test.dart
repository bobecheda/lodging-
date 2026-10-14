import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/app.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/password_hasher.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database_provider.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(env.db),
        clockProvider.overrideWithValue(env.clock),
        passwordHasherProvider.overrideWithValue(env.hasher),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> enter(WidgetTester tester, String key, String text) =>
      tester.enterText(find.byKey(ValueKey(key)), text);

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, String user, String password) async {
    await enter(tester, 'login.username', user);
    await enter(tester, 'login.password', password);
    await tap(tester, 'login.submit');
  }

  String location(ProviderContainer c) =>
      c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

  testWidgets('first run: setup creates the admin, then goes to login', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    expect(find.text('Set up this lodging'), findsOneWidget);

    await enter(tester, 'setup.lodgingName', 'Sunrise Lodge');
    await enter(tester, 'setup.fullName', 'Grace Owner');
    await enter(tester, 'setup.username', 'Owner');
    await enter(tester, 'setup.password', 'owner-pass');
    await enter(tester, 'setup.confirmPassword', 'owner-pass');
    await tap(tester, 'setup.submit');

    expect(location(app), Routes.login);
    expect(
      (await env.users.findByUsername('owner'))?.account.fullName,
      'Grace Owner',
    );
  });

  testWidgets('setup shows field errors and saves nothing', (tester) async {
    await pumpApp(tester);
    await tap(tester, 'setup.submit');
    expect(find.text('Enter the lodging name'), findsOneWidget);
    expect(await env.users.hasAnyUser(), isFalse);
  });

  testWidgets('once any user exists, the setup screen is unreachable', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    final app = await pumpApp(tester);
    expect(location(app), Routes.login);

    // Signed out: navigating to setup lands on login.
    app.read(routerProvider).go(Routes.setup);
    await tester.pumpAndSettle();
    expect(location(app), Routes.login);
    expect(find.text('Set up this lodging'), findsNothing);

    // Signed in: it lands on home instead.
    await signIn(tester, 'owner', 'owner-pass');
    app.read(routerProvider).go(Routes.setup);
    await tester.pumpAndSettle();
    expect(location(app), Routes.home);
    expect(find.text('Set up this lodging'), findsNothing);
  });

  testWidgets('an admin signs in straight to home without a shift', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    final app = await pumpApp(tester);
    await signIn(tester, 'OWNER', 'owner-pass');
    expect(location(app), Routes.home);
    expect(
      find.textContaining('Signed in as Grace Owner (Admin)'),
      findsOneWidget,
    );
    expect(find.textContaining('No shift open'), findsOneWidget);
  });

  testWidgets('a wrong password stays on login with a message', (tester) async {
    await env.users.createFirstAdmin(testSetup);
    final app = await pumpApp(tester);
    await signIn(tester, 'owner', 'wrong-pass');
    expect(location(app), Routes.login);
    expect(find.text('Wrong username or password.'), findsOneWidget);
  });

  testWidgets('must change password, then open a shift, then home (FD-1)', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    await env.addReceptionist('desk', mustChangePassword: true);
    final app = await pumpApp(tester);
    await signIn(tester, 'desk', 'desk-pass');
    expect(location(app), Routes.changePassword);

    // Nothing else is reachable until the password is changed.
    for (final route in [Routes.home, Routes.shift, Routes.login]) {
      app.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(location(app), Routes.changePassword, reason: route);
    }

    await enter(tester, 'password.new', 'my-own-pass');
    await enter(tester, 'password.confirm', 'my-own-pass');
    await tap(tester, 'password.submit');
    expect(location(app), Routes.shift);

    // No check-in or payment screen is reachable without an open shift.
    app.read(routerProvider).go(Routes.home);
    await tester.pumpAndSettle();
    expect(location(app), Routes.shift);

    await enter(tester, 'shift.float', '1,500');
    await tap(tester, 'shift.submit');
    expect(location(app), Routes.home);
    expect(find.textContaining('float KES 1,500'), findsOneWidget);
    expect(await env.auditFor('shift.open'), hasLength(1));
  });

  testWidgets('an invalid float is rejected on screen', (tester) async {
    await env.users.createFirstAdmin(testSetup);
    await env.addReceptionist('desk');
    await pumpApp(tester);
    await signIn(tester, 'desk', 'desk-pass');
    await enter(tester, 'shift.float', '12.50');
    await tap(tester, 'shift.submit');
    expect(find.textContaining('whole amount'), findsOneWidget);
    expect(await env.auditFor('shift.open'), isEmpty);
  });

  testWidgets("another receptionist is blocked by an open shift", (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    final desk = await env.addReceptionist('desk');
    await env.addReceptionist('tom');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 1000);
    final app = await pumpApp(tester);
    await signIn(tester, 'tom', 'desk-pass');
    expect(location(app), Routes.shift);
    expect(find.text('Another shift is open'), findsOneWidget);
    expect(find.textContaining("Desk DESK's shift"), findsOneWidget);
  });

  testWidgets('the shift owner resumes their shift after signing in again', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 800);
    final app = await pumpApp(tester);
    await signIn(tester, 'desk', 'desk-pass');
    expect(location(app), Routes.home);
    expect(find.textContaining('float KES 800'), findsOneWidget);
  });
}
