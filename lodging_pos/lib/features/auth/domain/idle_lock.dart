import '../../../core/settings/setting_defaults.dart';

const _minIdleLockMinutes = 1;
const _maxIdleLockMinutes = 240;

final _defaultIdleLockMinutes = int.parse(
  settingDefaults[SettingKeys.idleLockMinutes]!,
);

/// Minutes of inactivity before the session locks, from the
/// `idle_lock_minutes` setting. Anything missing, non-numeric or outside
/// 1–240 uses the default.
int idleLockMinutesFrom(String? setting) {
  final minutes = int.tryParse(setting?.trim() ?? '');
  if (minutes == null ||
      minutes < _minIdleLockMinutes ||
      minutes > _maxIdleLockMinutes) {
    return _defaultIdleLockMinutes;
  }
  return minutes;
}

/// True once [idleMinutes] have passed since [lastActivity]. A clock set back
/// (now before lastActivity) never locks early.
bool shouldLock({
  required DateTime lastActivity,
  required DateTime now,
  required int idleMinutes,
}) => now.difference(lastActivity) >= Duration(minutes: idleMinutes);
