import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/session.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late ProviderContainer app;
  late UserAccount desk;

  IdleLock lock() => app.read(idleLockProvider.notifier);
  UserAccount? signedIn() => app.read(sessionProvider);

  void idle(Duration d) => env.clock.advance(d);

  setUp(() async {
    env = TestEnv();
    app = ProviderContainer(overrides: env.overrides);
    desk = await env.addReceptionist('desk');
    app.read(idleLockProvider); // created at app start, before any sign-in
    app.read(sessionProvider.notifier).signIn(desk);
  });

  tearDown(() async {
    app.dispose();
    await env.close();
  });

  test('does not lock before 10 minutes of inactivity', () async {
    idle(const Duration(minutes: 9, seconds: 59));
    await lock().check();
    expect(signedIn(), isNotNull);
    expect(await env.auditFor('user.auto_lock'), isEmpty);
  });

  test(
    'locks at 10 minutes: signs out, audits user.auto_lock, says why',
    () async {
      idle(const Duration(minutes: 10));
      await lock().check();
      expect(signedIn(), isNull);
      expect(
        app.read(idleLockProvider),
        isA<IdleLockNotice>().having((n) => n.minutes, 'minutes', 10),
      );

      final entry = (await env.auditFor('user.auto_lock')).single;
      expect(entry.userId, desk.id);
      expect(entry.entityId, desk.id);
      expect(jsonDecode(entry.afterJson), {'idle_minutes': 10});
    },
  );

  test('activity restarts the countdown', () async {
    idle(const Duration(minutes: 9));
    lock().recordActivity();
    idle(const Duration(minutes: 9));
    await lock().check();
    expect(signedIn(), isNotNull);

    idle(const Duration(minutes: 1));
    await lock().check();
    expect(signedIn(), isNull);
  });

  test('uses the idle_lock_minutes setting', () async {
    await env.audit.writeWithAudit(
      action: 'settings.update',
      userId: null,
      body: (w) => w.update(
        env.db.settings,
        'idle_lock_minutes',
        const SettingsCompanion(value: Value('5')),
      ),
    );
    idle(const Duration(minutes: 5));
    await lock().check();
    expect(signedIn(), isNull);
    expect(
      app.read(idleLockProvider),
      isA<IdleLockNotice>().having((n) => n.minutes, 'minutes', 5),
    );
  });

  test('keeps the shift open', () async {
    final shifts = ShiftRepository(env.db, env.audit);
    final opened = await shifts.openShift(user: desk, openingFloat: 1000);
    idle(const Duration(minutes: 10));
    await lock().check();
    expect(signedIn(), isNull);
    expect((await shifts.openShiftOnThisDevice())?.id, opened.id);
  });

  test('audits a lock once even if checks overlap', () async {
    idle(const Duration(minutes: 10));
    await Future.wait([lock().check(), lock().check()]);
    expect(await env.auditFor('user.auto_lock'), hasLength(1));
  });

  test('a signed-out app never locks or audits', () async {
    app.read(sessionProvider.notifier).signOut();
    idle(const Duration(hours: 1));
    await lock().check();
    expect(await env.auditFor('user.auto_lock'), isEmpty);
    expect(app.read(idleLockProvider), isNull);
  });

  test(
    'signing in again clears the lock message and restarts the count',
    () async {
      idle(const Duration(minutes: 10));
      await lock().check();
      app.read(sessionProvider.notifier).signIn(desk);
      expect(app.read(idleLockProvider), isNull);
      expect(lock().lastActivity, env.clock.now());
    },
  );

  test(
    'Lock screen locks now: user.lock, not user.auto_lock; shift kept',
    () async {
      final shifts = ShiftRepository(env.db, env.audit);
      final opened = await shifts.openShift(user: desk, openingFloat: 1000);
      await lock().lockNow();
      expect(signedIn(), isNull);
      expect(app.read(idleLockProvider), isA<ManualLockNotice>());
      expect((await env.auditFor('user.lock')).single.userId, desk.id);
      expect(await env.auditFor('user.auto_lock'), isEmpty);
      expect((await shifts.openShiftOnThisDevice())?.id, opened.id);
    },
  );
}
