import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/features/setup/data/staff_repository.dart';
import 'package:lodging_pos/features/setup/presentation/staff_screen.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() async {
    env = TestEnv();
    await env.users.createFirstSupervisor(testSetup);
  });
  tearDown(() => env.close());

  StaffRepository staff() => StaffRepository(env.db, env.audit, env.hasher);

  Future<ProviderContainer> openStaff(WidgetTester tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'nav.${Routes.adminStaff}');
    expect(locationOf(app), Routes.adminStaff);
    return app;
  }

  Finder inRow(String username, Finder finder) => find.descendant(
    of: find.byKey(ValueKey('users.row.$username')),
    matching: finder,
  );

  testWidgets('your own row is marked and has no actions', (tester) async {
    await openStaff(tester);
    expect(find.text('Users and staff'), findsOneWidget);
    expect(inRow('supervisor', find.textContaining('(you)')), findsOneWidget);
    expect(inRow('supervisor', find.text('ACTIVE')), findsOneWidget);
    expect(inRow('supervisor', find.byType(OutlinedButton)), findsNothing);
    expect(find.byKey(const ValueKey('users.disable.owner')), findsNothing);
    expect(find.text('No housekeepers yet.'), findsOneWidget);
  });

  testWidgets('adds a receptionist who must set a password; a taken '
      'username is refused', (tester) async {
    await openStaff(tester);
    await enterKey(tester, 'addUser.fullName', 'Mary Wanjiku');
    await enterKey(tester, 'addUser.username', 'Mary');
    await enterKey(tester, 'addUser.password', 'temp-pass-1');
    await tapKey(tester, 'addUser.save');

    expect(find.text('Mary Wanjiku added.'), findsOneWidget);
    expect(inRow('mary', find.text('MUST SET PASSWORD')), findsOneWidget);
    expect(inRow('mary', find.text('mary · Receptionist')), findsOneWidget);

    await enterKey(tester, 'addUser.fullName', 'Mary Two');
    await enterKey(tester, 'addUser.username', 'MARY');
    await enterKey(tester, 'addUser.password', 'temp-pass-2');
    await tapKey(tester, 'addUser.save');
    expect(find.text('That username is taken.'), findsOneWidget);
  });

  testWidgets('reset password asks for a temporary one', (tester) async {
    final mary = await env.addReceptionist('mary');
    await openStaff(tester);
    await tapKey(tester, 'users.reset.mary');
    await enterKey(tester, 'reset.password', 'short');
    await tapKey(tester, 'reset.ok');
    expect(find.text('At least 8 characters'), findsOneWidget);

    await enterKey(tester, 'reset.password', 'new-temp-pass');
    await tapKey(tester, 'reset.ok');
    expect(find.textContaining('Password reset for'), findsOneWidget);
    expect(inRow('mary', find.text('MUST SET PASSWORD')), findsOneWidget);
    final row = (await staff().users()).firstWhere(
      (u) => u.account.id == mary.id,
    );
    expect(row.account.mustChangePassword, isTrue);
  });

  testWidgets('disabling a user whose shift is open warns, then disables; '
      'enable brings them back', (tester) async {
    final mary = await env.addReceptionist('mary');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: mary, openingFloat: 500);
    await openStaff(tester);
    expect(
      inRow('mary', find.textContaining('shift open since')),
      findsOneWidget,
    );

    await tapKey(tester, 'users.disable.mary');
    final warning = find.descendant(
      of: find.byKey(const ValueKey('disable.warning')),
      matching: find.textContaining(
        'Until shift close exists, no other receptionist can open a shift on '
        'this desk.',
      ),
    );
    expect(warning, findsOneWidget);
    await tapKey(tester, 'disable.ok');
    expect(inRow('mary', find.text('DISABLED')), findsOneWidget);
    expect(find.byKey(const ValueKey('users.reset.mary')), findsNothing);

    await tapKey(tester, 'users.enable.mary');
    expect(inRow('mary', find.text('ACTIVE')), findsOneWidget);
  });

  testWidgets('no open shift, no warning; Cancel keeps the account', (
    tester,
  ) async {
    await env.addReceptionist('mary');
    await openStaff(tester);
    await tapKey(tester, 'users.disable.mary');
    expect(find.byKey(const ValueKey('disable.warning')), findsNothing);
    await tapKey(tester, 'disable.cancel');
    expect(inRow('mary', find.text('ACTIVE')), findsOneWidget);
  });

  testWidgets('housekeepers: add with a masked phone, edit, deactivate and '
      'reactivate', (tester) async {
    await openStaff(tester);
    await enterKey(tester, 'hk.name', 'Rose Akinyi');
    await enterKey(tester, 'hk.phone', '0822 123 310');
    await tapKey(tester, 'hk.add');
    expect(
      find.text('Enter a Kenyan number starting 07 or 01, e.g. 0722 123 310.'),
      findsOneWidget,
    );
    await enterKey(tester, 'hk.phone', '+254 722 123 310');
    await tapKey(tester, 'hk.add');
    expect(find.text('Rose Akinyi'), findsOneWidget);
    expect(find.text('0722 ••• 310'), findsOneWidget);

    await enterKey(tester, 'hk.name', 'John Mutua');
    await tapKey(tester, 'hk.add');
    expect(find.text('No phone recorded'), findsOneWidget);

    final rose = (await staff().housekeepers()).firstWhere(
      (h) => h.fullName == 'Rose Akinyi',
    );
    await tapKey(tester, 'hk.edit.${rose.id}');
    await enterKey(tester, 'hk.editPhone', '0110 234 567');
    await tapKey(tester, 'hk.save');
    expect(find.text('0110 ••• 567'), findsOneWidget);

    await tapKey(tester, 'hk.edit.${rose.id}');
    await tapKey(tester, 'hk.deactivate');
    expect(find.text('INACTIVE'), findsOneWidget);
    await tapKey(tester, 'hk.edit.${rose.id}');
    await tapKey(tester, 'hk.reactivate');
    expect(find.text('INACTIVE'), findsNothing);
    expect(await env.auditFor('housekeeper.reactivate'), hasLength(1));
  });

  testWidgets('a receptionist cannot open Users & staff', (tester) async {
    await env.addReceptionist('desk');
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await enterKey(tester, 'shift.float', '500');
    await tapKey(tester, 'shift.submit');
    expect(find.text('Users & staff'), findsNothing);

    app.read(routerProvider).go(Routes.adminStaff);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.home);
    expect(find.byType(StaffScreen), findsNothing);
  });
}
