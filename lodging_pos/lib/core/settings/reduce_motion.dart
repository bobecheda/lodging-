import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audit/audit_writer.dart';
import '../auth/permissions.dart';
import '../auth/user_account.dart';
import '../database/database.dart';
import '../database/database_provider.dart';
import 'setting_defaults.dart';
import 'settings_repository.dart';

part 'reduce_motion.g.dart';

/// "Reduce motion" on this desk PC (v2 PR 3): Windows' "Show animations"
/// doesn't reach Flutter, so the supervisor turns animations off here
/// instead. The app then behaves as if the system asked for reduced
/// motion (`MediaQuery.disableAnimations`): everything switches at once.
/// Settings are never pulled from the cloud, so this stays per PC.
class ReduceMotionSetting {
  ReduceMotionSetting(this._db, this._audit, this._settings);

  final AppDatabase _db;
  final AuditWriter _audit;
  final SettingsRepository _settings;

  Future<bool> isOn() async =>
      await _settings.value(SettingKeys.reduceMotion) == 'true';

  /// Turns it on or off; needs [Permission.editSettings] (the supervisor).
  /// Audited as `settings.update`.
  Future<void> set(UserAccount user, {required bool on}) async {
    requirePermission(user, Permission.editSettings);
    const key = SettingKeys.reduceMotion;
    final value = on ? 'true' : 'false';
    final stored = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    if ((stored?.value ?? settingDefaults[key]) == value) return;
    await _audit.writeWithAudit(
      action: 'settings.update',
      userId: user.id,
      body: (w) async {
        if (stored != null) {
          await w.update(
            _db.settings,
            key,
            SettingsCompanion(value: Value(value), updatedBy: Value(user.id)),
          );
        } else {
          await w.insert(
            _db.settings,
            SettingsCompanion.insert(
              key: key,
              value: value,
              updatedBy: Value(user.id),
            ),
          );
        }
      },
    );
  }
}

@Riverpod(keepAlive: true)
ReduceMotionSetting reduceMotionSetting(Ref ref) => ReduceMotionSetting(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
  ref.watch(settingsRepositoryProvider),
);

/// Whether this desk has motion turned off. Invalidate after [set].
@Riverpod(keepAlive: true)
Future<bool> reduceMotion(Ref ref) =>
    ref.watch(reduceMotionSettingProvider).isOn();
