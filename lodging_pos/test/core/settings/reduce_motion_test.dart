import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/settings/reduce_motion.dart';
import 'package:lodging_pos/core/settings/settings_repository.dart';

import '../../helpers/fixtures.dart';

/// "Reduce motion" on this desk (v2 PR 3): off by default, the supervisor
/// turns it on, audited; a receptionist can't.
void main() {
  late TestEnv env;
  late ReduceMotionSetting setting;

  setUp(() {
    env = TestEnv();
    setting = ReduceMotionSetting(
      env.db,
      env.audit,
      SettingsRepository(env.db),
    );
  });
  tearDown(() => env.close());

  test(
    'off until the supervisor turns it on; audited once per change',
    () async {
      final supervisor = await env.createFirstSupervisor(testSetup);
      expect(await setting.isOn(), isFalse);
      await setting.set(supervisor, on: true);
      expect(await setting.isOn(), isTrue);
      await setting.set(supervisor, on: true); // no change, nothing written
      await setting.set(supervisor, on: false);
      expect(await setting.isOn(), isFalse);
      expect(
        (await env.auditFor('settings.update'))
            .where((a) => a.entityId == 'reduce_motion'),
        hasLength(2),
      );
    },
  );

  test('a receptionist can’t change it', () async {
    await env.createFirstSupervisor(testSetup);
    final mary = await env.addReceptionist('mary');
    await expectLater(
      setting.set(mary, on: true),
      throwsA(isA<NotPermitted>()),
    );
  });
}
