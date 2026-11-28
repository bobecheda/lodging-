import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/theme/theme.dart';
import 'package:lodging_pos/app/widgets/focus_ring.dart';
import 'package:lodging_pos/core/app_version.dart';
import 'package:lodging_pos/core/settings/reduce_motion.dart';
import 'package:lodging_pos/core/settings/settings_repository.dart';

import '../../helpers/fixtures.dart';

/// The v2 top bar (docs/ui-redesign-brief.md, "Desk navigation" and "Shell
/// states"): each role's tabs, Setup ▾ and More ▾, the drawer when the tabs
/// don't fit, the user menu, the status and the keyboard.
void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  /// The tab keys in the bar, in order (`nav.<route>`, `nav.group.<name>`).
  List<String> tabs(WidgetTester tester) => [
    for (final w in tester.widgetList(
      find.descendant(
        of: find.byKey(const ValueKey('shell.topBar')),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('nav.') &&
              !(w.key! as ValueKey<String>).value.startsWith('nav.badge'),
        ),
      ),
    ))
      (w.key! as ValueKey<String>).value.substring('nav.'.length),
  ];

  /// The app at [size]. The bundled fonts are loaded once per file
  /// (`test/flutter_test_config.dart`), so tabs measure as on the desk.
  Future<ProviderContainer> pumpAt(WidgetTester tester, Size size) async {
    final app = await pumpDeskApp(tester, env);
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> receptionistIn(WidgetTester tester) async {
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.submit');
  }

  group('each role’s tabs at 1366', () {
    testWidgets('the receptionist: Beds, Receipts, Guests, Refunds; Front '
        'desk', (tester) async {
      await env.createFirstSupervisor(testSetup);
      await env.addReceptionist('desk');
      await env.ensureDrawerStarted(counted: 500);
      await pumpAt(tester, deskSize);
      await receptionistIn(tester);
      expect(tabs(tester), [
        Routes.home,
        Routes.receipts,
        Routes.guests,
        Routes.refunds,
      ]);
      expect(find.text('Front desk'), findsOneWidget);
      expect(find.byKey(const ValueKey('shell.menu')), findsNothing);
      expect(find.byKey(const ValueKey('shell.indicator')), findsOneWidget);
    });

    testWidgets('the supervisor: Cash, More ▾ and Setup ▾ too', (tester) async {
      await env.createFirstSupervisor(testSetup);
      await pumpAt(tester, deskSize);
      await signInAs(tester, 'supervisor', 'super-pass');
      expect(tabs(tester), [
        Routes.home,
        Routes.receipts,
        Routes.guests,
        Routes.refunds,
        Routes.cash,
        'group.more',
        'group.setup',
      ]);
      expect(find.text('Supervisor'), findsWidgets);
    });

    testWidgets('the owner: Today, Cash, Prices, Staff and More ▾; no Setup', (
      tester,
    ) async {
      await env.createFirstSupervisor(testSetup);
      await pumpAt(tester, deskSize);
      await signInAs(tester, 'owner', 'owner-pass');
      expect(tabs(tester), [
        Routes.today,
        Routes.cash,
        Routes.adminPrices,
        Routes.adminStaff,
        'group.more',
      ]);
      expect(find.text('Prices'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
    });
  });

  testWidgets('Setup ▾ opens its menu; choosing a page goes there and moves '
      'the indicator; Esc closes it', (tester) async {
    await env.createFirstSupervisor(testSetup);
    final app = await pumpAt(tester, deskSize);
    await signInAs(tester, 'supervisor', 'super-pass');
    final indicator = find.byKey(const ValueKey('shell.indicator'));
    final under = tester.getTopLeft(indicator).dx;

    await tapKey(tester, 'nav.group.setup');
    expect(find.byKey(const ValueKey('shell.menuCard')), findsOneWidget);
    expect(find.text('Rooms & beds'), findsOneWidget);
    expect(find.text('Prices & settings'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell.menuCard')), findsNothing);

    await tapNav(tester, Routes.adminRooms);
    expect(locationOf(app), Routes.adminRooms);
    expect(find.byKey(const ValueKey('shell.menuCard')), findsNothing);
    // The indicator now sits under Setup ▾.
    expect(tester.getTopLeft(indicator).dx, greaterThan(under));
  });

  group('the drawer when the tabs don’t fit (768 wide)', () {
    testWidgets('a menu button instead of tabs, the name hidden; the '
        'drawer has the pages, the sections and the foot', (tester) async {
      await env.createFirstSupervisor(testSetup);
      final app = await pumpAt(tester, const Size(768, 1024));
      await signInAs(tester, 'supervisor', 'super-pass');
      expect(tabs(tester), isEmpty);
      expect(find.byKey(const ValueKey('shell.menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('shell.userName')), findsNothing);
      expect(find.byKey(const ValueKey('shell.lock')), findsOneWidget);

      await tapKey(tester, 'shell.menu');
      expect(find.byKey(const ValueKey('shell.drawer')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('shell.drawer'))).width,
        Sizes.drawerWidth,
      );
      expect(find.text('Setup'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.byKey(const ValueKey('shell.drawer.lock')), findsOneWidget);
      expect(find.byKey(const ValueKey('shell.drawer.status')), findsOneWidget);
      expect(find.byKey(const ValueKey('shell.version')), findsOneWidget);

      await tapKey(tester, 'nav.${Routes.receipts}');
      expect(find.byKey(const ValueKey('shell.drawer')), findsNothing);
      expect(locationOf(app), Routes.receipts);
    });

    testWidgets('closes on X, Esc and the scrim; focus goes back to the '
        'menu button', (tester) async {
      await env.createFirstSupervisor(testSetup);
      await pumpAt(tester, const Size(768, 1024));
      await signInAs(tester, 'supervisor', 'super-pass');
      final drawer = find.byKey(const ValueKey('shell.drawer'));

      await tapKey(tester, 'shell.menu');
      await tapKey(tester, 'shell.drawer.close');
      expect(drawer, findsNothing);

      await tapKey(tester, 'shell.menu');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(drawer, findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'shell.menu',
        reason: 'focus returns to the menu button',
      );

      await tapKey(tester, 'shell.menu');
      await tester.tapAt(const Offset(700, 500)); // the scrim
      await tester.pumpAndSettle();
      expect(drawer, findsNothing);
    });
  });

  group('the user menu', () {
    testWidgets('the receptionist closes their shift from it: a focused flow '
        'with no navigation, and a way back', (tester) async {
      await env.createFirstSupervisor(testSetup);
      await env.addReceptionist('desk');
      await env.ensureDrawerStarted(counted: 500);
      final app = await pumpAt(tester, deskSize);
      await receptionistIn(tester);
      await tapUserMenu(tester, 'shell.closeShift');
      expect(locationOf(app), Routes.closeShift);
      expect(find.byKey(const ValueKey('shell.topBar')), findsNothing);
      await tapKey(tester, 'closeShift.back');
      expect(locationOf(app), Routes.home);
    });

    testWidgets('the owner changes their password from it; the supervisor '
        'without a shift has no menu', (tester) async {
      await env.createFirstSupervisor(testSetup);
      await pumpAt(tester, deskSize);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'shell.user');
      expect(find.text('Change my password'), findsOneWidget);
      expect(find.text('Close shift'), findsNothing);
    });

    testWidgets('a supervisor without a shift of their own: the menu still '
        'opens, with only the version line (story/desk-db-guards)', (
      tester,
    ) async {
      await env.createFirstSupervisor(testSetup);
      await pumpAt(tester, deskSize);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'shell.user');
      expect(find.byKey(const ValueKey('shell.menuCard')), findsOneWidget);
      expect(find.text('Close shift'), findsNothing);
      final version = find.descendant(
        of: find.byKey(const ValueKey('shell.menuCard')),
        matching: find.byKey(const ValueKey('shell.version')),
      );
      expect(
        tester.widget<Text>(version).data,
        versionLine(AppBuild.current, schemaVersion: env.db.schemaVersion),
      );
      // Read, not focused: a screen reader finds it; Tab never stops on it.
      expect(find.bySemanticsLabel(RegExp('^Desk ')), findsOneWidget);
    });
  });

  testWidgets('the status: sync not set up shows as a butter pill and opens '
      'the Cloud sync panel', (tester) async {
    await env.createFirstSupervisor(testSetup);
    await pumpAt(tester, deskSize);
    await signInAs(tester, 'supervisor', 'super-pass');
    expect(find.text('Sync not set up'), findsOneWidget);
    await tapKey(tester, 'shell.syncPill');
    expect(find.text('Cloud sync'), findsWidgets);
  });

  testWidgets('the wordmark is the lodging’s name; the subtitle the role', (
    tester,
  ) async {
    await env.createFirstSupervisor(testSetup);
    await pumpAt(tester, deskSize);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(find.text('Sunrise Lodge'), findsOneWidget);
    expect(find.byKey(const ValueKey('shell.role')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('shell.role'))).data,
      'Owner',
    );
  });

  testWidgets('keyboard: the focus ring shows on the tab the Tab key '
      'reaches, never for the mouse', (tester) async {
    await env.createFirstSupervisor(testSetup);
    await env.addReceptionist('desk');
    await env.ensureDrawerStarted(counted: 500);
    await pumpAt(tester, deskSize);
    await receptionistIn(tester);
    bool ringShows() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any(
          (p) =>
              p.foregroundPainter is FocusRingPainter &&
              (p.foregroundPainter! as FocusRingPainter).show,
        );
    await tapNav(tester, Routes.receipts);
    expect(ringShows(), isFalse);
    for (var i = 0; i < 3 && !ringShows(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(ringShows(), isTrue);
  });

  testWidgets('"Reduce motion" on this desk: the app runs with animations '
      'off', (tester) async {
    final supervisor = await env.createFirstSupervisor(testSetup);
    await ReduceMotionSetting(
      env.db,
      env.audit,
      SettingsRepository(env.db),
    ).set(supervisor, on: true);
    await pumpAt(tester, deskSize);
    await signInAs(tester, 'supervisor', 'super-pass');
    final context = tester.element(find.byKey(const ValueKey('shell.topBar')));
    expect(LodgingMotion.of(context).reduced, isTrue);
  });

  group('the floating bar (story/ui-floating-nav)', () {
    testWidgets('12 px clear of the window, 64 tall; the page starts under '
        'it', (tester) async {
      await env.createFirstSupervisor(testSetup);
      await env.addReceptionist('desk');
      await env.ensureDrawerStarted(counted: 500);
      await pumpAt(tester, deskSize);
      await receptionistIn(tester);
      final bar = tester.getRect(find.byKey(const ValueKey('shell.topBar')));
      expect(bar.left, Sizes.topBarMargin);
      expect(bar.top, Sizes.topBarMargin);
      expect(bar.right, deskSize.width - Sizes.topBarMargin);
      expect(bar.height, Sizes.topBar);
      expect(
        tester.getRect(find.byKey(const ValueKey('board.now'))).top,
        greaterThan(bar.bottom),
      );
    });

    // As before the bar floated: the supervisor's seven tabs stay in the
    // bar at 1366 with the name, and at 1280 without it; never the drawer.
    for (final (width, name) in const [(1366.0, true), (1280.0, false)]) {
      testWidgets('the supervisor at $width: every tab in the bar', (
        tester,
      ) async {
        await env.createFirstSupervisor(testSetup);
        await pumpAt(tester, Size(width, 768));
        await signInAs(tester, 'supervisor', 'super-pass');
        expect(tabs(tester), hasLength(7));
        expect(find.byKey(const ValueKey('shell.menu')), findsNothing);
        expect(
          find.byKey(const ValueKey('shell.userName')),
          name ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
