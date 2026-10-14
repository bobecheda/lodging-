import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../clock/clock.dart';
import '../database/database.dart';
import '../database/database_provider.dart';

part 'audit_writer.g.dart';

/// JSON for audit and outbox payloads: SQL column names as keys (build.yaml)
/// and ISO-8601 UTC timestamps, so payloads map 1:1 to the Postgres mirror.
const auditJsonSerializer = ValueSerializer.defaults(
  serializeDateTimeValuesAsString: true,
);

final _actionPattern = RegExp(r'^[a-z_]+\.[a-z_]+$');

/// Written only by [AuditWriter] itself or by the database's `onCreate`.
const _systemTables = {'audit_log', 'outbox', 'device'};

/// Changed inside the transaction, but never audited or synced.
const _localOnlyTables = {'receipt_counter'};

/// The single write path. Repositories never write to drift directly.
class AuditWriter {
  AuditWriter(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  /// Runs [body] in one transaction. For every synced row [body] inserts or
  /// updates through [AuditedWrites], it also writes one `audit_log` row
  /// (before/after of that row, tagged with [action]) and outbox rows for the
  /// business row and the audit row, in write order.
  ///
  /// If anything throws, nothing is saved.
  ///
  /// [action] is `entity.verb`, e.g. `stay.check_in`. [userId] is the user
  /// doing it.
  Future<T> writeWithAudit<T>({
    required String action,
    required String? userId,
    required Future<T> Function(AuditedWrites w) body,
  }) {
    _checkAction(action);
    return _db.transaction(() async {
      final w = AuditedWrites._(_db, _clock.now(), await _db.deviceId());
      final result = await body(w);
      if (w._changes.isEmpty) {
        throw StateError(
          '$action changed no synced rows; use recordEvent for audit-only '
          'entries',
        );
      }
      for (final c in w._changes) {
        await w._enqueue(c.table, c.id, c.afterJson);
        await w._audit(
          action: action,
          userId: userId,
          entity: c.table,
          entityId: c.id,
          beforeJson: c.beforeJson,
          afterJson: c.afterJson,
        );
      }
      return result;
    });
  }

  /// Writes an audit entry for an event that changes no business rows, such
  /// as `user.login` or `user.login_failed` ([userId] null).
  Future<void> recordEvent({
    required String action,
    required String? userId,
    required String entity,
    required String entityId,
    Map<String, Object?> details = const {},
  }) {
    _checkAction(action);
    return _db.transaction(() async {
      final w = AuditedWrites._(_db, _clock.now(), await _db.deviceId());
      await w._audit(
        action: action,
        userId: userId,
        entity: entity,
        entityId: entityId,
        beforeJson: null,
        afterJson: jsonEncode(details),
      );
    });
  }

  static void _checkAction(String action) {
    if (!_actionPattern.hasMatch(action)) {
      throw ArgumentError.value(action, 'action', 'must be entity.verb');
    }
  }
}

/// The writes allowed inside [AuditWriter.writeWithAudit].
///
/// Reads through the database inside the body see the transaction, so
/// repositories may query `db` directly before writing.
class AuditedWrites {
  AuditedWrites._(this._db, this.now, this.deviceId);

  final AppDatabase _db;

  /// "Now" for this whole write. Use it for business timestamps too
  /// (e.g. `check_in_at`) so they match the audit entry.
  final DateTime now;

  /// This install's device id.
  final String deviceId;

  final _changes = <_Change>[];

  String newId() => const Uuid().v4();

  /// Inserts [row] and returns it as stored.
  ///
  /// Build [row] with the companion's `.insert(...)`, so business fields are
  /// checked at compile time. `id` defaults to a new UUID (client default).
  ///
  /// On synced tables, stamps `created_at`, `updated_at` (= [now]) and
  /// `device_id`, overriding any value in [row]. Their client defaults throw,
  /// so only this method can insert synced rows.
  Future<D> insert<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    Insertable<D> row,
  ) async {
    final name = _writableName(table);
    // The generic equivalent of companion.copyWith(...): Insertable has no
    // copyWith, but its column map can be overridden.
    final values = row.toColumns(false);
    final synced = !_localOnlyTables.contains(name);
    if (synced) {
      values['created_at'] = Variable<DateTime>(now);
      values['updated_at'] = Variable<DateTime>(now);
      values['device_id'] = Variable<String>(deviceId);
    }

    final inserted = await _db
        .into(table)
        .insertReturning(RawValuesInsertable<D>(values));
    if (synced) _record(table, before: null, after: inserted);
    return inserted;
  }

  /// Updates the row whose primary key is [id] with [changes] and returns it
  /// as stored. Throws if the row does not exist.
  ///
  /// On synced tables, stamps `updated_at` = [now]. [changes] may not touch
  /// the primary key, `created_at` or `device_id`.
  Future<D> update<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    String id,
    Insertable<D> changes,
  ) async {
    final name = _writableName(table);
    final pk = _primaryKey(table);
    final values = changes.toColumns(false);
    for (final column in {pk.name, 'created_at', 'device_id'}) {
      if (values.containsKey(column)) {
        throw ArgumentError('$name.$column cannot be changed by an update');
      }
    }
    if (values.isEmpty) throw ArgumentError('No changes for $name $id');

    final synced = !_localOnlyTables.contains(name);
    if (synced) values['updated_at'] = Variable<DateTime>(now);

    final before = await (_db.select(
      table,
    )..where((_) => pk.equals(id))).getSingleOrNull();
    if (before == null) throw StateError('$name $id not found');

    final after =
        (await (_db.update(table)..where((_) => pk.equals(id))).writeReturning(
          RawValuesInsertable<D>(values),
        )).single;
    if (synced) _record(table, before: before, after: after);
    return after;
  }

  void _record(
    TableInfo table, {
    required DataClass? before,
    required DataClass after,
  }) {
    final afterMap = after.toJson(serializer: auditJsonSerializer);
    _changes.add(
      _Change(
        table: table.actualTableName,
        id: afterMap[_primaryKey(table).name] as String,
        beforeJson: before == null
            ? null
            : jsonEncode(before.toJson(serializer: auditJsonSerializer)),
        afterJson: jsonEncode(afterMap),
      ),
    );
  }

  Future<void> _audit({
    required String action,
    required String? userId,
    required String entity,
    required String entityId,
    required String? beforeJson,
    required String afterJson,
  }) async {
    final row = await _db
        .into(_db.auditLog)
        .insertReturning(
          AuditLogCompanion.insert(
            createdAt: Value(now),
            updatedAt: Value(now),
            deviceId: Value(deviceId),
            at: now,
            userId: Value(userId),
            action: action,
            entity: entity,
            entityId: entityId,
            beforeJson: Value(beforeJson),
            afterJson: afterJson,
          ),
        );
    await _enqueue(
      'audit_log',
      row.id,
      jsonEncode(row.toJson(serializer: auditJsonSerializer)),
    );
  }

  Future<void> _enqueue(String table, String rowId, String payloadJson) => _db
      .into(_db.outbox)
      .insert(
        OutboxCompanion.insert(
          targetTable: table,
          targetRowId: rowId,
          payloadJson: payloadJson,
          createdAt: now,
        ),
      );

  static String _writableName(TableInfo table) {
    final name = table.actualTableName;
    if (_systemTables.contains(name)) {
      throw ArgumentError('$name is not written through writeWithAudit');
    }
    return name;
  }

  static GeneratedColumn<String> _primaryKey(TableInfo table) =>
      table.$primaryKey.single as GeneratedColumn<String>;
}

class _Change {
  const _Change({
    required this.table,
    required this.id,
    required this.beforeJson,
    required this.afterJson,
  });

  final String table;
  final String id;
  final String? beforeJson;
  final String afterJson;
}

@Riverpod(keepAlive: true)
AuditWriter auditWriter(Ref ref) =>
    AuditWriter(ref.watch(appDatabaseProvider), ref.watch(clockProvider));
