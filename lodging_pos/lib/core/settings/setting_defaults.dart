/// Every setting's default, in one place. The v1 seed writes these, and the
/// settings reader falls back to them for any key missing from the database,
/// so a new setting only needs an entry here.
const settingDefaults = {
  'checkout_time': '10:00',
  'grace_minutes': '60',
  'receipt_prefix': 'R',
  'idle_lock_minutes': '10',
  // Daily backups: an optional second folder (e.g. a USB drive) each backup
  // is also copied to. Empty: none. A path on this desk PC.
  'backup_second_folder': '',
  // Story B: a closing count (and a drawer check) matches within this many
  // KES either way. Owner-only (`setCashRules`); UB40 keeps 0, so overs are
  // reviewed like shorts.
  'shift_count_tolerance': '0',
};

abstract final class SettingKeys {
  static const lodgingName = 'lodging_name';
  static const checkoutTime = 'checkout_time';
  static const graceMinutes = 'grace_minutes';
  static const receiptPrefix = 'receipt_prefix';
  static const idleLockMinutes = 'idle_lock_minutes';
  static const backupSecondFolder = 'backup_second_folder';
  static const shiftCountTolerance = 'shift_count_tolerance';
}
