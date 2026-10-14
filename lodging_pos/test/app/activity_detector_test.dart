import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/app.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  Future<ProviderContainer> signedInApp(WidgetTester tester) async {
    await env.users.createFirstAdmin(testSetup);
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 1000);
    final app = ProviderContainer(overrides: env.overrides);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: app, child: const App()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('login.username')),
      'desk',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'desk-pass',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();
    return app;
  }

  String location(ProviderContainer app) =>
      app.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

  /// Moves the clock on, then checks whether an input counted as activity.
  Future<void> expectActivity(
    WidgetTester tester,
    ProviderContainer app,
    Future<void> Function() input,
  ) async {
    env.clock.advance(const Duration(minutes: 5));
    await input();
    await tester.pump();
    expect(app.read(idleLockProvider.notifier).lastActivity, env.clock.now());
  }

  testWidgets('clicks, scrolling, key presses and mouse movement count', (
    tester,
  ) async {
    final app = await signedInApp(tester);
    final centre = tester.getCenter(find.byType(Scaffold).first);

    // Click.
    await expectActivity(tester, app, () => tester.tapAt(centre));

    // Mouse movement with no button pressed.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await expectActivity(tester, app, () => mouse.moveTo(centre));

    // Scroll wheel.
    await expectActivity(
      tester,
      app,
      () => tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 40)),
      ),
    );

    // Key press.
    await expectActivity(
      tester,
      app,
      () => tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft),
    );
  });

  testWidgets('after 10 idle minutes: login with an empty username and a message; '
      'signing back in resumes the open shift', (tester) async {
    final app = await signedInApp(tester);
    expect(location(app), Routes.home);

    env.clock.advance(const Duration(minutes: 10));
    await app.read(idleLockProvider.notifier).check();
    await tester.pumpAndSettle();

    expect(location(app), Routes.login);
    expect(
      find.text(
        'Signed out after 10 minutes of inactivity. Your shift is still open.',
      ),
      findsOneWidget,
    );
    final username = tester.widget<TextField>(
      find.byKey(const ValueKey('login.username')),
    );
    expect(username.controller!.text, isEmpty);
    expect(await env.auditFor('user.auto_lock'), hasLength(1));

    await tester.enterText(
      find.byKey(const ValueKey('login.username')),
      'desk',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'desk-pass',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();
    expect(location(app), Routes.home);
    expect(find.textContaining('float KES 1,000'), findsOneWidget);
    expect(await env.auditFor('shift.open'), hasLength(1));
  });
}
