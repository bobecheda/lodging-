import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/shell/desk_shell.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  /// The sidebar's item labels, in order.
  List<String> navLabels(WidgetTester tester) => [
    for (final e in tester.widgetList<InkWell>(
      find.byWidgetPredicate(
        (w) =>
            w is InkWell &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('nav.'),
      ),
    ))
      (e.key! as ValueKey<String>).value.substring('nav.'.length),
  ];

  testWidgets('a database from before the owner role: the one-time owner '
      'screen comes before sign-in; then the owner signs in to Today', (
    tester,
  ) async {
    // A supervisor but no owner, as after the v6 upgrade.
    await env.audit.writeWithAudit(
      action: 'user.create',
      userId: null,
      body: (w) => w.insert(
        env.db.users,
        UsersCompanion.insert(
          fullName: 'Grace Supervisor',
          username: 'supervisor',
          passwordHash: 'not-used',
          role: Role.supervisor.name,
          mustChangePassword: false,
        ),
      ),
    );
    final app = await pumpDeskApp(tester, env);
    expect(locationOf(app), Routes.setup);
    expect(find.text("Create the owner's account"), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.lodgingName')), findsNothing);

    await enterKey(tester, 'setup.fullName', 'Amina Owner');
    await enterKey(tester, 'setup.username', 'Owner');
    await enterKey(tester, 'setup.password', 'owner-pass');
    await enterKey(tester, 'setup.confirmPassword', 'owner-pass');
    await tapKey(tester, 'setup.submit');
    expect(locationOf(app), Routes.login);

    await signInAs(tester, 'owner', 'owner-pass');
    expect(locationOf(app), Routes.today); // no shift screen
    expect(navLabels(tester), [
      Routes.today,
      Routes.shifts,
      Routes.adminPrices,
      Routes.adminStaff,
    ]);
    expect(find.text('Prices'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('SETUP · SUPERVISOR'), findsNothing);
    expect(find.text('Bed board'), findsNothing);
    expect(app.read(deskNavItemsProvider), isNotEmpty);
  });

  testWidgets('Today: the four cards from real stays, payments and a '
      'refund awaiting approval', (tester) async {
    // Wed 14 Oct 10:00: last week's Wednesday, KES 1,400 by now.
    env.clock.set(nairobiInstant(2026, 10, 14, 9));
    final supervisor = await env.createFirstSupervisor(testSetup);
    final desk = await env.addReceptionist('desk');
    final rooms = RoomsRepository(env.db, env.audit);
    final r5 = await rooms.createRoom(
      supervisor,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe, // 700
        bedBCategoryId: SeedIds.comfort, // 600
      ),
    );
    final r6 = await rooms.createRoom(
      supervisor,
      const NewRoom(
        number: '6',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    await env.checkIn(r6.beds.single.id, by: desk, nights: 2); // 1,400
    // Wed 21 Oct: one stay leaves early (refund awaiting), one checks in.
    env.clock.set(nairobiInstant(2026, 10, 20, 19));
    final early = await env.checkIn(r5.beds.first.id, by: desk, nights: 3);
    env.clock.set(nairobiInstant(2026, 10, 21, 9));
    await env.checkIn(r5.beds.last.id, by: desk); // 600 today
    await env.checkOut(early, by: desk); // 2 nights refund requested
    env.clock.set(nairobiInstant(2026, 10, 21, 14));

    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(locationOf(app), Routes.today);
    expect(text(tester, 'today.date'), 'Wednesday 21 October');

    // Needs your attention: the refund.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('today.attention.count')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Refund to approve'), findsOneWidget);
    expect(find.text('Test Guest · Room 5 A · 2 nights'), findsOneWidget);
    expect(find.text('KES 1,400'), findsWidgets);

    // Today's money: 600 today against 1,400 last Wednesday by 14:00.
    expect(text(tester, 'today.money.total'), 'KES 600');
    // ▼ drawn as an icon in ink-soft, then the words.
    expect(text(tester, 'today.money.vs'), '57% vs last Wednesday (KES 1,400)');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('today.money')),
        matching: find.byIcon(Icons.arrow_drop_down_rounded),
      ),
      findsOneWidget,
    );
    // Screen readers hear the whole line, arrow included.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == '▼ 57% vs last Wednesday (KES 1,400)',
      ),
      findsOneWidget,
    );
    expect(text(tester, 'today.money.cash'), 'KES 600');
    expect(text(tester, 'today.money.mpesa'), 'KES 0');

    // Beds: 5B occupied; 6A never checked out (paid to Fri): overstay,
    // still in use; 5A to clean.
    expect(text(tester, 'today.beds.inUse'), '2 of 3');
    expect(text(tester, 'today.beds.percent'), '67% occupied');
    Finder chip(String key, String count) => find.descendant(
      of: find.byKey(ValueKey('today.beds.$key')),
      matching: find.text(count),
    );
    expect(chip('occupied', '1'), findsOneWidget);
    expect(chip('overstay', '1'), findsOneWidget);
    expect(chip('toClean', '1'), findsOneWidget);
    expect(chip('ready', '0'), findsOneWidget);

    // This month: 1,400 + 2,100 + 600 = 4,100 received; no refund paid.
    expect(text(tester, 'today.month.revenue'), 'KES 4,100');
    expect(find.text('THIS MONTH · OCTOBER'), findsOneWidget);
  });

  testWidgets("the owner's Staff: adds a supervisor; receptionists aren't "
      'listed', (tester) async {
    await env.createFirstSupervisor(testSetup);
    await env.addReceptionist('desk');
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'nav.${Routes.adminStaff}');
    expect(locationOf(app), Routes.adminStaff);
    expect(find.text('Staff'), findsWidgets);
    expect(find.byKey(const ValueKey('users.row.desk')), findsNothing);
    expect(find.byKey(const ValueKey('users.row.supervisor')), findsOneWidget);
    expect(find.text('Add a supervisor'), findsOneWidget);

    await enterKey(tester, 'addUser.fullName', 'Joseph Otieno');
    await enterKey(tester, 'addUser.username', 'joseph');
    await enterKey(tester, 'addUser.password', 'temp-pass-2');
    await tapKey(tester, 'addUser.save');
    expect(find.byKey(const ValueKey('users.row.joseph')), findsOneWidget);
    final joseph = (await env.users.findByUsername('joseph'))!.account;
    expect(joseph.role, Role.supervisor);
  });
}
