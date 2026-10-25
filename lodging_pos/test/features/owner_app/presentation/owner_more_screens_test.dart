import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';

import '../../../helpers/fake_owner_cloud.dart';
import '../../../helpers/fixtures.dart' show enterKey, tapKey, testOwner;
import 'owner_app_test.dart' show pumpOwnerApp, phone, smallPhone;

/// owner-app-3 on the phone: More (Figma "07 More"), Shifts, the Audit
/// trail, Staff and Change password.
void main() {
  final now = nairobiInstant(2026, 10, 24, 9, 30); // Saturday
  late FixedClock clock;
  late FakeOwnerCloud cloud;

  setUp(() {
    clock = FixedClock(now);
    cloud = FakeOwnerCloud(serverNow: () => clock.now())
      ..stored = FakeOwnerCloud.owner;
    seedOwnerLodging(cloud, now);
    seedAuditTrail(cloud, now);
  });

  String text(WidgetTester tester, String key) {
    final finder = find.byKey(ValueKey(key));
    if (tester.widget(finder) case Text(:final data?)) return data;
    return [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: finder, matching: find.byType(Text)),
      ))
        t.data,
    ].join(' ');
  }

  Future<void> reveal(WidgetTester tester, String key, String list) =>
      tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(ValueKey(list)),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  Future<void> open(
    WidgetTester tester,
    String item, {
    Size size = phone,
  }) async {
    await pumpOwnerApp(tester, cloud, clock, size: size);
    await tapKey(tester, 'owner.nav.more');
    if (item.isNotEmpty) await tapKey(tester, 'owner.more.$item');
  }

  testWidgets('More: the menu, Reports not yet, who is signed in and the '
      'desk’s last sync', (tester) async {
    await open(tester, '');
    expect(find.text('Shifts'), findsOneWidget);
    expect(find.text('Monthly report (PDF) · coming next'), findsOneWidget);
    await tapKey(tester, 'owner.more.reports');
    expect(find.byKey(const ValueKey('owner.more')), findsOneWidget);
    expect(find.text('Owner · UB40'), findsOneWidget);
    expect(text(tester, 'owner.more.email'), testOwnerEmail);
    expect(text(tester, 'owner.more.desk'), 'Desk last synced 3 min ago');
  });

  testWidgets('Shifts: the open one with what it has taken; closed ones '
      'with short or over in words', (tester) async {
    await open(tester, 'shifts');
    // Grace's open shift took KES 1,400 by M-Pesa and 700 cash, voided.
    expect(find.text('OPEN'), findsOneWidget);
    expect(text(tester, 'owner.shift.s-3.cash'), 'KES 0');
    expect(find.text('KES 1,400'), findsWidgets);
    expect(text(tester, 'owner.shift.s-1.variance'), 'KES 300 short');
    expect(find.text('“Gave change from my pocket”'), findsOneWidget);
    await reveal(tester, 'owner.shift.s-2.variance', 'owner.shifts');
    expect(text(tester, 'owner.shift.s-2.variance'), 'KES 200 over');
    expect(find.text('Closed by Grace Akinyi'), findsOneWidget);
    await tapKey(tester, 'more.back');
    expect(find.byKey(const ValueKey('owner.more')), findsOneWidget);
  });

  testWidgets('Audit trail: newest first, in words, where; details only '
      'without guest data; filters', (tester) async {
    await open(tester, 'audit');
    expect(text(tester, 'audit.entry.0'), contains('Voided a record'));
    expect(
      text(tester, 'audit.entry.0.detail'),
      'Payment voided · “Wrong bed”',
    );
    expect(text(tester, 'audit.entry.1.detail'), 'KES 1,400 · Waiting');
    expect(text(tester, 'audit.entry.2.detail'), 'Deluxe: KES 650 → KES 700');
    expect(
      text(tester, 'audit.entry.2.who'),
      'Amina Owner · on the phone · today 09:00',
    );
    expect(text(tester, 'audit.entry.3'), contains('Registered a guest'));
    expect(find.byKey(const ValueKey('audit.entry.3.detail')), findsNothing);
    expect(find.textContaining('+2567'), findsNothing);
    expect(
      text(tester, 'audit.entry.4.who'),
      'John Otieno · on the desk · today 08:40',
    );

    await tapKey(tester, 'audit.kind.prices');
    expect(text(tester, 'audit.entry.0'), contains('Changed a price'));
    expect(find.byKey(const ValueKey('audit.entry.1')), findsNothing);
    await tapKey(tester, 'audit.kind.all');
    await tapKey(tester, 'audit.person');
    await tester.tap(find.text('John Otieno').last);
    await tester.pumpAndSettle();
    expect(text(tester, 'audit.entry.0'), contains('Asked for a refund'));
  });

  testWidgets('Staff: everyone, roles, who is disabled', (tester) async {
    await open(tester, 'staff');
    expect(text(tester, 'owner.staff.owner'), contains('Owner · owner'));
    expect(
      text(tester, 'owner.staff.peter'),
      contains('Receptionist · peter · Disabled'),
    );
  });

  group('Change password', () {
    Future<void> fill(
      WidgetTester tester,
      String current,
      String next, [
      String? repeat,
    ]) async {
      await enterKey(tester, 'ownerPassword.current', current);
      await enterKey(tester, 'ownerPassword.new', next);
      await enterKey(tester, 'ownerPassword.repeat', repeat ?? next);
      await tapKey(tester, 'ownerPassword.save');
    }

    Future<void> openPassword(WidgetTester tester, {Size size = phone}) async {
      await pumpOwnerApp(tester, cloud, clock, size: size);
      await tapKey(tester, 'owner.nav.more');
      await reveal(tester, 'owner.changePassword', 'owner.more');
      await tapKey(tester, 'owner.changePassword');
    }

    testWidgets('recorded first, then set, then the other sessions ended', (
      tester,
    ) async {
      await openPassword(tester);
      await fill(tester, testOwner.password, 'set-on-phone-1');
      expect(find.text('Password changed.'), findsOneWidget);
      expect(cloud.password, 'set-on-phone-1');
      expect(cloud.passwordSteps, ['verify', 'update', 'signOutOthers']);
      final rpcs = [for (final (name, _) in cloud.calls) name];
      expect(rpcs.indexOf('record_password_change'), greaterThan(-1));
      expect(cloud.table('owner_password_changes'), hasLength(1));
      expect(cloud.table('audit_log').last['action'], 'user.change_password');
    });

    testWidgets('wrong current, too short, not repeated, offline: refused, '
        'nothing recorded', (tester) async {
      await openPassword(tester);
      await fill(tester, 'not-it-at-all', 'set-on-phone-1');
      expect(
        text(tester, 'ownerPassword.problem'),
        'That isn’t your current password.',
      );
      await fill(tester, testOwner.password, 'short');
      expect(text(tester, 'ownerPassword.problem'), 'At least 8 characters');
      await fill(tester, testOwner.password, 'set-on-phone-1', 'other-1234');
      expect(
        text(tester, 'ownerPassword.problem'),
        'The new passwords don’t match.',
      );
      cloud.offline = true;
      await fill(tester, testOwner.password, 'set-on-phone-1');
      expect(
        text(tester, 'ownerPassword.problem'),
        'Changing your password needs an internet connection.',
      );
      expect(cloud.table('owner_password_changes'), isEmpty);
      expect(cloud.password, testOwner.password);
    });

    testWidgets('recorded, but setting it fails: the error, the password '
        'unchanged, and trying again works', (tester) async {
      await openPassword(tester);
      cloud.failPasswordUpdate = true;
      await fill(tester, testOwner.password, 'set-on-phone-1');
      expect(
        text(tester, 'ownerPassword.problem'),
        startsWith('The new password wasn’t saved'),
      );
      expect(cloud.table('owner_password_changes'), hasLength(1));
      expect(cloud.password, testOwner.password);
      await fill(tester, testOwner.password, 'set-on-phone-1');
      expect(cloud.password, 'set-on-phone-1');
    });
  });

  group('fits a phone', () {
    for (final size in [smallPhone, phone]) {
      final label = '${size.width.toInt()}×${size.height.toInt()}';
      testWidgets('$label: More, Shifts, Audit trail, Staff, Change password', (
        tester,
      ) async {
        await open(tester, 'shifts', size: size);
        await tester.drag(
          find.byKey(const ValueKey('owner.shifts')),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        await tapKey(tester, 'more.back');
        await tapKey(tester, 'owner.more.audit');
        await tapKey(tester, 'audit.kind.money');
        await tester.drag(
          find.byKey(const ValueKey('owner.audit')),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        await tapKey(tester, 'more.back');
        await tapKey(tester, 'owner.more.staff');
        await tapKey(tester, 'more.back');
        await reveal(tester, 'owner.changePassword', 'owner.more');
        await tapKey(tester, 'owner.changePassword');
        await reveal(tester, 'ownerPassword.save', 'owner.password');
        await tapKey(tester, 'ownerPassword.save');
        // Any overflow fails the test on its own.
        expect(tester.takeException(), isNull);
      });
    }
  });
}
