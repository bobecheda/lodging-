/// Prices and settings (AD-3): rules for bed category prices and names, and
/// for the lodging's settings. Pure Dart.
library;

import '../../../core/clock/clock_time.dart';
import '../../../core/money/kes.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../auth/domain/idle_lock.dart';
import 'bed_category.dart';

// ── Prices ───────────────────────────────────────────────────────────────

/// A price per night is whole KES in this range.
const priceRange = (min: 1, max: 100000);

/// Null if [price] can be saved.
String? priceError(int? price) {
  if (price == null) return 'Enter a price.';
  if (price < priceRange.min) {
    return 'The price must be at least ${formatKes(priceRange.min)}.';
  }
  if (price > priceRange.max) {
    return 'The price can be at most ${formatKes(priceRange.max)}.';
  }
  return null;
}

/// One price the owner is about to change.
final class PriceChange {
  const PriceChange({
    required this.categoryId,
    required this.name,
    required this.oldPrice,
    required this.newPrice,
  });

  final String categoryId;
  final String name;
  final int oldPrice;
  final int newPrice;

  /// For the confirmation dialog: `Deluxe: 700 → 750`.
  String get label => '$name: ${_amount(oldPrice)} → ${_amount(newPrice)}';

  static String _amount(int kes) => formatKes(kes).substring('KES '.length);
}

/// The prices in [edits] (category id → new price) that differ from
/// [categories], in category order.
List<PriceChange> priceChanges(
  List<BedCategory> categories,
  Map<String, int> edits,
) => [
  for (final c in categories)
    if (edits[c.id] case final price? when price != c.pricePerNight)
      PriceChange(
        categoryId: c.id,
        name: c.name,
        oldPrice: c.pricePerNight,
        newPrice: price,
      ),
];

// ── Categories ───────────────────────────────────────────────────────────

const _maxCategoryName = 30;

String normalizeCategoryName(String name) => name.trim();

/// Null if [name] is a usable new category name: 1–30 characters after
/// trimming, not already used by any of [existing] (ignoring case; the
/// database enforces the same with `COLLATE NOCASE`).
String? categoryNameError(
  String name, {
  required Iterable<BedCategory> existing,
}) {
  final trimmed = normalizeCategoryName(name);
  if (trimmed.isEmpty) return 'Enter a name.';
  if (trimmed.length > _maxCategoryName) {
    return 'Use at most $_maxCategoryName characters.';
  }
  final taken = existing
      .where((c) => c.name.toLowerCase() == trimmed.toLowerCase())
      .firstOrNull;
  if (taken != null) return '${taken.name} already exists.';
  return null;
}

/// Why [category] can't be closed, or null if it can. Active beds count even
/// in a room closed for repairs, since reopening the room would let them.
String? closeCategoryBlocker(BedCategory category, {required int activeBeds}) {
  if (!category.isActive || activeBeds == 0) return null;
  final beds = activeBeds == 1 ? '1 bed uses' : '$activeBeds beds use';
  final them = activeBeds == 1 ? 'it' : 'them';
  return '$beds ${category.name}. Move $them to another category first.';
}

// ── Settings ─────────────────────────────────────────────────────────────

/// Checkout time choices: 06:00–14:00 in 30-minute steps.
final List<ClockTime> checkoutTimeOptions = List.unmodifiable([
  for (var m = 6 * 60; m <= 14 * 60; m += 30) ClockTime(m ~/ 60, m % 60),
]);

const graceMinutesRange = (min: 0, max: 180);

/// Minutes of grace after `paid_until` (BR-6), from the `grace_minutes`
/// setting. Anything missing or outside [graceMinutesRange] uses the
/// default (60).
int graceMinutesFrom(String? setting) {
  if (setting == null || _graceError(setting) != null) {
    return int.parse(settingDefaults[SettingKeys.graceMinutes]!);
  }
  return int.parse(setting.trim());
}

const _maxLodgingName = 60;
final _receiptPrefix = RegExp(r'^[A-Z]{1,4}$');

enum SettingsField {
  lodgingName,
  checkoutTime,
  graceMinutes,
  idleLockMinutes,
  receiptPrefix,
}

/// The "Rules and receipts" form. Minutes stay as typed until validated.
final class SettingsInput {
  const SettingsInput({
    required this.lodgingName,
    required this.checkoutTime,
    required this.graceMinutes,
    required this.idleLockMinutes,
    required this.receiptPrefix,
  });

  /// From stored settings; a value the rules can't use falls back to its
  /// default, so the form always opens valid.
  factory SettingsInput.fromStored(Map<String, String> stored) {
    String value(String key) => stored[key] ?? settingDefaults[key] ?? '';
    String usable(String key, String? Function(String) error) {
      final v = value(key);
      return error(v) == null ? v.trim() : settingDefaults[key]!;
    }

    final checkout = ClockTime.tryParse(value(SettingKeys.checkoutTime));
    return SettingsInput(
      lodgingName: value(SettingKeys.lodgingName),
      checkoutTime: checkout != null && checkoutTimeOptions.contains(checkout)
          ? checkout
          : ClockTime.tryParse(settingDefaults[SettingKeys.checkoutTime]!)!,
      graceMinutes: usable(SettingKeys.graceMinutes, _graceError),
      idleLockMinutes: usable(
        SettingKeys.idleLockMinutes,
        idleLockMinutesError,
      ),
      receiptPrefix: usable(SettingKeys.receiptPrefix, _prefixError),
    );
  }

  final String lodgingName;
  final ClockTime checkoutTime;
  final String graceMinutes;
  final String idleLockMinutes;
  final String receiptPrefix;

  /// What gets saved: trimmed text, the prefix in capitals.
  SettingsInput normalized() => SettingsInput(
    lodgingName: lodgingName.trim(),
    checkoutTime: checkoutTime,
    graceMinutes: graceMinutes.trim(),
    idleLockMinutes: idleLockMinutes.trim(),
    receiptPrefix: receiptPrefix.trim().toUpperCase(),
  );

  /// Setting key → stored value.
  Map<String, String> toStored() => {
    SettingKeys.lodgingName: lodgingName,
    SettingKeys.checkoutTime: checkoutTime.format(),
    SettingKeys.graceMinutes: graceMinutes,
    SettingKeys.idleLockMinutes: idleLockMinutes,
    SettingKeys.receiptPrefix: receiptPrefix,
  };
}

String? _graceError(String text) {
  final minutes = int.tryParse(text.trim());
  if (minutes == null ||
      minutes < graceMinutesRange.min ||
      minutes > graceMinutesRange.max) {
    return 'Enter whole minutes from ${graceMinutesRange.min} to '
        '${graceMinutesRange.max}.';
  }
  return null;
}

String? _prefixError(String text) =>
    _receiptPrefix.hasMatch(text.trim().toUpperCase())
    ? null
    : 'Use 1 to 4 letters.';

/// Errors per field; empty if the form can be saved.
Map<SettingsField, String> validateSettings(SettingsInput input) {
  final name = input.lodgingName.trim();
  return {
    if (name.isEmpty)
      SettingsField.lodgingName: 'Enter the lodging name.'
    else if (name.length > _maxLodgingName)
      SettingsField.lodgingName: 'Use at most $_maxLodgingName characters.',
    if (!checkoutTimeOptions.contains(input.checkoutTime))
      SettingsField.checkoutTime: 'Choose a time from 06:00 to 14:00.',
    SettingsField.graceMinutes: ?_graceError(input.graceMinutes),
    SettingsField.idleLockMinutes: ?idleLockMinutesError(input.idleLockMinutes),
    SettingsField.receiptPrefix: ?_prefixError(input.receiptPrefix),
  };
}
