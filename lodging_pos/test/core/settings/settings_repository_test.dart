import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/settings/setting_defaults.dart';
import 'package:lodging_pos/core/settings/settings_repository.dart';

import '../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late SettingsRepository settings;

  setUp(() {
    env = TestEnv();
    settings = SettingsRepository(env.db);
  });
  tearDown(() => env.close());

  test('the defaults map holds every default in one place', () {
    expect(settingDefaults, {
      'checkout_time': '10:00',
      'grace_minutes': '60',
      'receipt_prefix': 'R',
      'idle_lock_minutes': '10',
      'backup_second_folder': '',
    });
  });

  test('a new database is seeded with every default', () async {
    for (final MapEntry(:key, :value) in settingDefaults.entries) {
      expect(await settings.value(key), value, reason: key);
    }
  });

  test('a stored value wins over the default', () async {
    await env.users.createFirstSupervisor(testSetup);
    expect(await settings.value('lodging_name'), 'Sunrise Lodge');
  });

  test('a key missing from the database falls back to its default', () async {
    // e.g. a database created before the setting existed.
    await (env.db.delete(
      env.db.settings,
    )..where((s) => s.key.equals('idle_lock_minutes'))).go();
    expect(await settings.value('idle_lock_minutes'), '10');
  });

  test('an unknown key with no default is an error', () async {
    await expectLater(settings.value('no_such_key'), throwsArgumentError);
  });
}
