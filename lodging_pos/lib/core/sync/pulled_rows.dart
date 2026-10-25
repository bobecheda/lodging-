import 'package:drift/drift.dart';

import '../audit/audit_writer.dart';
import '../clock/clock.dart';
import '../database/database.dart';
import 'cloud.dart';
import 'sync_store.dart';

/// A pulled row can't be applied here (e.g. a decision that clashes with a
/// different one already on this desk). The pull stops; nothing is
/// overwritten.
final class PullConflict implements Exception {
  const PullConflict(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The second write path, and the only one besides `writeWithAudit` that
/// writes synced tables (test/policy/single_write_path_test.dart): rows the
/// pull brings from the owner's side, written as they are. They get no
/// audit rows here (their own audit rows come with them) and no outbox
/// rows (they are never pushed back).
class PulledRows {
  PulledRows(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  /// Applies one page and moves the cursor to [cursor], in one transaction:
  /// a crash replays the page, and replaying is harmless. A row already
  /// here (by id) is skipped: decisions this desk wrote in the cloud first,
  /// prices it set, and anything sent before. Returns how many rows changed
  /// something. Throws [PullConflict].
  Future<int> apply(List<PulledRow> rows, {required int cursor}) =>
      _db.transaction(() async {
        var changed = 0;
        for (final r in rows) {
          try {
            if (await _apply(r)) changed++;
          } on PullConflict {
            rethrow;
          } catch (e) {
            throw PullConflict(
              '${r.table} ${r.row['id']} from the cloud can’t be kept here: $e',
            );
          }
        }
        await SyncStore(_db).set(SyncStore.pullAfter, cursor);
        return changed;
      });

  Future<bool> _apply(PulledRow r) async => switch (r.table) {
    'refund_decisions' => _refundDecision(
      RefundDecisionRow.fromJson(r.row, serializer: auditJsonSerializer),
    ),
    'price_decisions' => _priceDecision(
      PriceDecisionRow.fromJson(r.row, serializer: auditJsonSerializer),
    ),
    'bed_categories' => _price(
      r.row['id']! as String,
      (r.row['price_per_night']! as num).toInt(),
    ),
    'audit_log' => _auditRow(
      AuditLogRow.fromJson(r.row, serializer: auditJsonSerializer),
    ),
    'owner_password_changes' => _passwordChange(
      DateTime.parse(r.row['changed_at']! as String).toUtc(),
    ),
    _ => throw PullConflict('The cloud sent rows of ${r.table}.'),
  };

  Future<bool> _refundDecision(RefundDecisionRow d) async {
    final here = await (_db.select(
      _db.refundDecisions,
    )..where((x) => x.refundId.equals(d.refundId))).getSingleOrNull();
    if (here != null) {
      if (here.id == d.id) return false;
      throw PullConflict(
        'The cloud has another decision for refund ${d.refundId} than this '
        'desk (${here.decision} here, ${d.decision} there).',
      );
    }
    await _db.into(_db.refundDecisions).insert(d);
    return true;
  }

  Future<bool> _priceDecision(PriceDecisionRow d) async {
    final here = await (_db.select(
      _db.priceDecisions,
    )..where((x) => x.requestId.equals(d.requestId))).getSingleOrNull();
    if (here != null) {
      if (here.id == d.id) return false;
      throw PullConflict(
        'The cloud has another decision for price request ${d.requestId} '
        'than this desk (${here.decision} here, ${d.decision} there).',
      );
    }
    await _db.into(_db.priceDecisions).insert(d);
    return true;
  }

  /// The owner's price for [categoryId]: new check-ins pay it from now
  /// (BR-3); stays keep theirs. `updated_at` moves on, as every update
  /// here must.
  Future<bool> _price(String categoryId, int price) async {
    final here = await (_db.select(
      _db.bedCategories,
    )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
    if (here == null) {
      throw PullConflict('The cloud priced category $categoryId, not here.');
    }
    if (here.pricePerNight == price) return false;
    final now = _clock.now();
    final next = now.isAfter(here.updatedAt)
        ? now
        : here.updatedAt.add(const Duration(milliseconds: 1));
    await (_db.update(
      _db.bedCategories,
    )..where((c) => c.id.equals(categoryId))).write(
      BedCategoriesCompanion(
        pricePerNight: Value(price),
        updatedAt: Value(next),
      ),
    );
    return true;
  }

  /// The owner's password was changed (here or on the phone) at [at]:
  /// kept as the latest the cloud knows. Nothing else is stored; no
  /// password ever comes down.
  Future<bool> _passwordChange(DateTime at) async {
    final store = SyncStore(_db);
    final known = await store.get(SyncStore.passwordCloudAt);
    if (known != null && !at.isAfter(DateTime.parse(known))) return false;
    await store.set(SyncStore.passwordCloudAt, at.toIso8601String());
    return true;
  }

  Future<bool> _auditRow(AuditLogRow a) async {
    final here = await (_db.select(
      _db.auditLog,
    )..where((x) => x.id.equals(a.id))).getSingleOrNull();
    if (here != null) return false;
    await _db.into(_db.auditLog).insert(a);
    return true;
  }
}
