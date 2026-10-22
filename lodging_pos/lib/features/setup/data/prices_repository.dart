import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../price_requests/data/price_requests_repository.dart';
import '../domain/bed_category.dart';
import '../domain/prices_settings.dart';

/// A category with the number of active beds using it (active even in a
/// room closed for repairs).
final class CategoryUsage {
  const CategoryUsage(this.category, this.activeBeds);
  final BedCategory category;
  final int activeBeds;
}

/// Prices that failed [priceError], by category id.
class InvalidPrices implements Exception {
  const InvalidPrices(this.errors);
  final Map<String, String> errors;
}

/// A settings form that failed [validateSettings].
class InvalidSettings implements Exception {
  const InvalidSettings(this.errors);
  final Map<SettingsField, String> errors;
}

/// A category rule refused the change; [message] is shown to the supervisor.
class CategoryRuleViolation implements Exception {
  const CategoryRuleViolation(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Prices and settings (AD-3). Category writes need
/// [Permission.editPrices], settings writes [Permission.editSettings]; every
/// write goes through writeWithAudit with the old and new values, and every
/// rule check runs inside its transaction.
class PricesRepository {
  PricesRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditWriter _audit;

  /// All categories in sort order, with their active beds.
  Future<List<CategoryUsage>> categories() async {
    final rows = await (_db.select(
      _db.bedCategories,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
    final beds = await _activeBedsByCategory();
    return [
      for (final r in rows) CategoryUsage(_toCategory(r), beds[r.id] ?? 0),
    ];
  }

  /// Saves [prices] (category id → new price) that differ from the stored
  /// ones: one `price.update` audit row per changed category. Returns the
  /// number changed.
  Future<int> savePrices(UserAccount user, Map<String, int> prices) async {
    requirePermission(user, Permission.editPrices);
    final errors = {
      for (final MapEntry(:key, :value) in prices.entries)
        key: ?priceError(value),
    };
    if (errors.isNotEmpty) throw InvalidPrices(errors);
    // The writer refuses a call that changes nothing.
    final pending = priceChanges([
      for (final u in await categories()) u.category,
    ], prices);
    if (pending.isEmpty) return 0;

    return _audit.writeWithAudit(
      action: 'price.update',
      userId: user.id,
      body: (w) async {
        final current = await _db.select(_db.bedCategories).get();
        final unknown = prices.keys.toSet().difference({
          for (final c in current) c.id,
        });
        if (unknown.isNotEmpty) {
          throw ArgumentError.value(unknown, 'prices', 'unknown categories');
        }
        final changes = priceChanges([
          for (final c in current) _toCategory(c),
        ], prices);
        for (final change in changes) {
          await w.update(
            _db.bedCategories,
            change.categoryId,
            BedCategoriesCompanion(pricePerNight: Value(change.newPrice)),
          );
        }
        return changes.length;
      },
    );
  }

  /// Adds an active category at the end of the list (`category.create`).
  Future<BedCategory> addCategory(
    UserAccount user, {
    required String name,
    required int pricePerNight,
  }) async {
    requirePermission(user, Permission.editPrices);
    final priceProblem = priceError(pricePerNight);
    if (priceProblem != null) throw CategoryRuleViolation(priceProblem);
    final row = await _audit.writeWithAudit(
      action: 'category.create',
      userId: user.id,
      body: (w) async {
        final current = await _db.select(_db.bedCategories).get();
        final nameProblem = categoryNameError(
          name,
          existing: [for (final c in current) _toCategory(c)],
        );
        if (nameProblem != null) throw CategoryRuleViolation(nameProblem);
        final lastSort = current.fold(
          0,
          (m, c) => c.sortOrder > m ? c.sortOrder : m,
        );
        return w.insert(
          _db.bedCategories,
          BedCategoriesCompanion.insert(
            name: normalizeCategoryName(name),
            pricePerNight: pricePerNight,
            sortOrder: lastSort + 1,
          ),
        );
      },
    );
    return _toCategory(row);
  }

  /// Closes a category so new beds can't use it (`category.update`). Refused
  /// while active beds use it. Its waiting price request is withdrawn in the
  /// same transaction (`price.request_withdraw`, "Category closed").
  Future<void> closeCategory(UserAccount user, String categoryId) =>
      _setActive(user, categoryId, active: false);

  /// Reopens a closed category (`category.update`).
  Future<void> reopenCategory(UserAccount user, String categoryId) =>
      _setActive(user, categoryId, active: true);

  Future<void> _setActive(
    UserAccount user,
    String categoryId, {
    required bool active,
  }) async {
    requirePermission(user, Permission.editPrices);
    final current = await (_db.select(
      _db.bedCategories,
    )..where((c) => c.id.equals(categoryId))).getSingle();
    if (current.isActive == active) return;
    await _audit.writeWithAudit(
      action: 'category.update',
      userId: user.id,
      body: (w) async {
        final row = await (_db.select(
          _db.bedCategories,
        )..where((c) => c.id.equals(categoryId))).getSingle();
        if (!active) {
          final beds = (await _activeBedsByCategory())[categoryId] ?? 0;
          final blocker = closeCategoryBlocker(
            _toCategory(row),
            activeBeds: beds,
          );
          if (blocker != null) throw CategoryRuleViolation(blocker);
        }
        await w.update(
          _db.bedCategories,
          categoryId,
          BedCategoriesCompanion(isActive: Value(active)),
        );
        // Its waiting price request goes with it: a reopened category
        // starts with none.
        if (!active) {
          await PriceRequestsRepository.withdrawOnClose(
            w,
            _db,
            user,
            categoryId,
          );
        }
      },
    );
  }

  /// The settings form as stored (unusable values fall back to defaults).
  Future<SettingsInput> settings() async {
    return SettingsInput.fromStored(await _storedSettings());
  }

  /// The number the next receipt on this device will get.
  Future<int> nextReceiptNumber() async {
    final deviceId = await _db.deviceId();
    final row = await (_db.select(
      _db.receiptCounter,
    )..where((r) => r.deviceId.equals(deviceId))).getSingleOrNull();
    return row?.nextNumber ?? 1;
  }

  /// Saves the settings that changed: one `settings.update` audit row per
  /// key, with its old and new value. Returns the number changed.
  Future<int> saveSettings(UserAccount user, SettingsInput input) async {
    requirePermission(user, Permission.editSettings);
    final errors = validateSettings(input);
    if (errors.isNotEmpty) throw InvalidSettings(errors);
    final wanted = input.normalized().toStored();
    // The writer refuses a call that changes nothing.
    final before = await _storedSettings();
    if (wanted.entries.every((e) => before[e.key] == e.value)) return 0;

    return _audit.writeWithAudit(
      action: 'settings.update',
      userId: user.id,
      body: (w) async {
        final stored = await _storedSettings();
        var changed = 0;
        for (final MapEntry(:key, :value) in wanted.entries) {
          if (stored[key] == value) continue;
          changed++;
          if (stored.containsKey(key)) {
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
        }
        return changed;
      },
    );
  }

  Future<Map<String, String>> _storedSettings() async => {
    for (final r in await _db.select(_db.settings).get()) r.key: r.value,
  };

  Future<Map<String, int>> _activeBedsByCategory() async {
    final count = _db.beds.id.count();
    final rows =
        await (_db.selectOnly(_db.beds)
              ..addColumns([_db.beds.categoryId, count])
              ..where(_db.beds.isActive.equals(true))
              ..groupBy([_db.beds.categoryId]))
            .get();
    return {for (final r in rows) r.read(_db.beds.categoryId)!: r.read(count)!};
  }

  static BedCategory _toCategory(BedCategoryRow r) => BedCategory(
    id: r.id,
    name: r.name,
    pricePerNight: r.pricePerNight,
    sortOrder: r.sortOrder,
    isActive: r.isActive,
  );
}
