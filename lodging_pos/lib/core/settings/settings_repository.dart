import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/database_provider.dart';
import 'setting_defaults.dart';

part 'settings_repository.g.dart';

/// Reads settings. Editing them belongs to AD-3 (through writeWithAudit).
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  /// The stored value, or its default from [settingDefaults] if the key is
  /// missing (e.g. a database created before the setting existed). Throws
  /// for a key that is neither stored nor has a default.
  Future<String> value(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    if (row != null) return row.value;
    final fallback = settingDefaults[key];
    if (fallback == null) {
      throw ArgumentError.value(key, 'key', 'no such setting');
    }
    return fallback;
  }
}

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    SettingsRepository(ref.watch(appDatabaseProvider));
