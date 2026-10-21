import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  /// The receptionist signed in on the desk, working in their open shift.
  Future<ProviderContainer> signedInApp(WidgetTester tester) async {
    await env.createFirstSupervisor(testSetup);
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 1000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    return app;
  }

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
    final centre = tester.getCenter(find.text('Bed board').last);

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

  testWidgets(
    'after 10 idle minutes: lock screen with an empty username; signing back '
    'in resumes the open shift',
    (tester) async {
      final app = await signedInApp(tester);
      expect(locationOf(app), Routes.home);

      env.clock.advance(const Duration(minutes: 10));
      await app.read(idleLockProvider.notifier).check();
      await tester.pumpAndSettle();

      expect(locationOf(app), Routes.login);
      expect(find.text('Screen locked after 10 minutes idle'), findsOneWidget);
      expect(
        find.text('The open shift is kept. Sign in to carry on.'),
        findsOneWidget,
      );
      final username = tester.widget<TextField>(
        find.byKey(const ValueKey('login.username')),
      );
      expect(username.controller!.text, isEmpty);
      expect(await env.auditFor('user.auto_lock'), hasLength(1));

      await signInAs(tester, 'desk', 'desk-pass');
      // Back to the same shift: the resume card first.
      expect(locationOf(app), Routes.shift);
      await tapKey(tester, 'shift.continue');
      expect(locationOf(app), Routes.home);
      expect(find.text('Bed board'), findsWidgets);
      expect(
        (await env.db.select(env.db.shifts).getSingle()).openingFloat,
        1000,
      );
      expect(await env.auditFor('shift.open'), hasLength(1));
    },
  );

  testWidgets('the sidebar Lock screen button locks now (user.lock)', (
    tester,
  ) async {
    final app = await signedInApp(tester);
    await tapKey(tester, 'shell.lock');
    expect(locationOf(app), Routes.login);
    expect(find.text('Screen locked'), findsWidgets);
    expect(await env.auditFor('user.lock'), hasLength(1));
    expect(await env.auditFor('user.auto_lock'), isEmpty);
  });
}
