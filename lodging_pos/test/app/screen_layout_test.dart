import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../helpers/fixtures.dart';

/// Every restyled screen at the front-desk laptop's size (1366×768) with the
/// real fonts: any overflow is reported as an error and fails the test.
void main() {
  late TestEnv env;

  setUpAll(loadAppFonts);
  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  Future<void> expectCleanLayout(
    WidgetTester tester,
    ProviderContainer app,
    String route,
    String visibleText,
  ) async {
    await tester.pumpAndSettle();
    expect(locationOf(app), route);
    expect(find.text(visibleText), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(tester.view.physicalSize, deskSize);
  }

  Future<void> withOwner() async =>
      env.users.createFirstAdmin(testSetup).then((_) {});

  testWidgets('first-run setup', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await expectCleanLayout(tester, app, Routes.setup, 'Set up this lodging');
  });

  testWidgets('first-run setup with every field error', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await tapKey(tester, 'setup.submit');
    await expectCleanLayout(
      tester,
      app,
      Routes.setup,
      'Enter the lodging name',
    );
  });

  testWidgets('sign in', (tester) async {
    await withOwner();
    final app = await pumpDeskApp(tester, env);
    await expectCleanLayout(tester, app, Routes.login, 'Sign in');
  });

  testWidgets('sign in with a wrong password', (tester) async {
    await withOwner();
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'wrong-pass');
    await expectCleanLayout(
      tester,
      app,
      Routes.login,
      'Wrong username or password. Try again.',
    );
  });

  testWidgets('lock screen after idle, shift kept', (tester) async {
    await withOwner();
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 1000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    env.clock.advance(const Duration(minutes: 10));
    await app.read(idleLockProvider.notifier).check();
    await expectCleanLayout(
      tester,
      app,
      Routes.login,
      'Screen locked after 10 minutes idle',
    );
  });

  testWidgets('lock screen after Lock screen', (tester) async {
    await withOwner();
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'shell.lock');
    await expectCleanLayout(tester, app, Routes.login, 'Screen locked');
  });

  testWidgets('change password', (tester) async {
    await withOwner();
    await env.addReceptionist('fresh', mustChangePassword: true);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'fresh', 'desk-pass');
    await expectCleanLayout(
      tester,
      app,
      Routes.changePassword,
      'Choose a new password',
    );
  });

  testWidgets('open shift, with an error', (tester) async {
    await withOwner();
    await env.addReceptionist('desk');
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.submit');
    await expectCleanLayout(
      tester,
      app,
      Routes.shift,
      'Enter the opening cash float',
    );
  });

  testWidgets('resume shift', (tester) async {
    await withOwner();
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 2000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await expectCleanLayout(tester, app, Routes.shift, 'Continue my shift');
  });

  testWidgets('shift blocked by another receptionist', (tester) async {
    await withOwner();
    final desk = await env.addReceptionist('desk');
    await env.addReceptionist('tom');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 2000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'tom', 'desk-pass');
    await expectCleanLayout(
      tester,
      app,
      Routes.shift,
      "Desk's shift must be closed first",
    );
  });

  testWidgets('desk shell: owner', (tester) async {
    await withOwner();
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await expectCleanLayout(tester, app, Routes.home, 'Owner · admin');
  });

  testWidgets('desk shell: receptionist in a shift', (tester) async {
    await withOwner();
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 1000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    await expectCleanLayout(
      tester,
      app,
      Routes.home,
      'Receptionist · shift since 22:00',
    );
  });
}
