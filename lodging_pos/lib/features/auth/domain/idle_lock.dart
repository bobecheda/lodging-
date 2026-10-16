import '../../../core/settings/setting_defaults.dart';

/// `idle_lock_minutes` must be whole minutes in this range (AD-3). One rule
/// for the settings form and the lock itself.
const idleLockMinutesRange = (min: 1, max: 60);

final _defaultIdleLockMinutes = int.parse(
  settingDefaults[SettingKeys.idleLockMinutes]!,
);

/// Null if [text] is whole minutes within [idleLockMinutesRange].
String? idleLockMinutesError(String text) {
  final minutes = int.tryParse(text.trim());
  if (minutes == null ||
      minutes < idleLockMinutesRange.min ||
      minutes > idleLockMinutesRange.max) {
    return 'Enter whole minutes from ${idleLockMinutesRange.min} to '
        '${idleLockMinutesRange.max}.';
  }
  return null;
}

/// Minutes of inactivity before the session locks, from the
/// `idle_lock_minutes` setting. Anything missing or failing
/// [idleLockMinutesError] uses the default (10).
int idleLockMinutesFrom(String? setting) {
  if (setting == null || idleLockMinutesError(setting) != null) {
    return _defaultIdleLockMinutes;
  }
  return int.parse(setting.trim());
}

/// True once [idleMinutes] have passed since [lastActivity]. A clock set back
/// (now before lastActivity) never locks early.
bool shouldLock({
  required DateTime lastActivity,
  required DateTime now,
  required int idleMinutes,
}) => now.difference(lastActivity) >= Duration(minutes: idleMinutes);
