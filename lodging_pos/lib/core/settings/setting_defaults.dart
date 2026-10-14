/// Every setting's default, in one place. The v1 seed writes these, and the
/// settings reader falls back to them for any key missing from the database,
/// so a new setting only needs an entry here.
const settingDefaults = {
  'block_hours': '12',
  'grace_minutes': '60',
  'receipt_prefix': 'R',
  'idle_lock_minutes': '10',
};

abstract final class SettingKeys {
  static const lodgingName = 'lodging_name';
  static const blockHours = 'block_hours';
  static const graceMinutes = 'grace_minutes';
  static const receiptPrefix = 'receipt_prefix';
  static const idleLockMinutes = 'idle_lock_minutes';
}
