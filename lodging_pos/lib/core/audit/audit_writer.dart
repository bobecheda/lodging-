import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../clock/clock.dart';
import '../contacts/id_number.dart';
import '../contacts/phone.dart';
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

/// Columns replaced by [_redacted] in audit JSON (never in the business row's
/// outbox payload): secrets, and guest personal data that must stay
/// purgeable under the Data Protection Act while audit_log is append-only.
const _redactedColumns = {
  'users': {'password_hash'},
  'guests': {'full_name'},
};
const _redacted = '[redacted]';

/// Columns kept in audit JSON only masked, so a change is still visible
/// without storing the value: phones `0722•••310`, ID numbers `••••3921`.
const _maskedColumns = <String, Map<String, String Function(String)>>{
  'guests': {'phone': _maskPhoneCompact, 'id_number': maskIdNumber},
  'housekeepers': {'phone': _maskPhoneCompact},
  'refunds': {'payout_phone': _maskPhoneCompact},
};

String _maskPhoneCompact(String phone) => maskPhone(phone, compact: true);

/// The single write path. Repositories never write to drift directly.
class AuditWriter {
  AuditWriter(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  /// Runs [body] in one transaction. For every synced row [body] inserts or
  /// updates through [AuditedWrites], it writes, at that moment, the outbox
  /// row for the business row, one `audit_log` row (tagged with [action]) and
  /// the outbox row for the audit row. All audit rows of one call share an
  /// `operation_id`.
  ///
  /// Writes [body] started but did not await are awaited before commit;
  /// using the [AuditedWrites] after this call returns throws. If any write
  /// fails, nothing is saved.
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
      final w = await _start(action, userId);
      try {
        final result = await body(w);
        await Future.wait(w._pending);
        if (w._writes == 0) {
          throw StateError(
            '$action changed no synced rows; use recordEvent for audit-only '
            'entries',
          );
        }
        return result;
      } finally {
        w._closed = true;
      }
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
      final w = await _start(action, userId);
      await w._audit(
        entity: entity,
        entityId: entityId,
        beforeJson: null,
        afterJson: jsonEncode(details),
      );
    });
  }

  Future<AuditedWrites> _start(String action, String? userId) async =>
      AuditedWrites._(
        _db,
        now: _clock.now(),
        deviceId: await _db.deviceId(),
        operationId: const Uuid().v4(),
        action: action,
        userId: userId,
      );

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
  AuditedWrites._(
    this._db, {
    required this.now,
    required this.deviceId,
    required this.operationId,
    required this._action,
    required this._userId,
  });

  final AppDatabase _db;
  final String _action;
  final String? _userId;

  /// "Now" for this whole write. Use it for business timestamps too
  /// (e.g. `check_in_at`) so they match the audit entry.
  final DateTime now;

  /// This install's device id.
  final String deviceId;

  /// `audit_log.operation_id` for every audit row of this call.
  final String operationId;

  final _pending = <Future<Object?>>[];
  var _writes = 0;
  var _closed = false;

  String newId() => const Uuid().v4();

  /// Inserts [row] and returns it as stored.
  ///
  /// Build [row] with the companion's `.insert(...)`, so business fields are
  /// checked at compile time. `id` gets a new UUID (client default) unless
  /// [row] has one to link rows in this transaction.
  ///
  /// On synced tables, stamps `created_at`, `updated_at` (= [now]) and
  /// `device_id` in the column map, overriding any value in [row]. Their
  /// client defaults throw, so only this method can fill them.
  ///
  /// [action] overrides the call's action for this row's audit entry, so one
  /// call (one `operation_id`) can record several actions.
  Future<D> insert<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    Insertable<D> row, {
    String? action,
  }) => _track(() async {
    if (action != null) AuditWriter._checkAction(action);
    final name = _writableName(table);
    final synced = !_localOnlyTables.contains(name);
    final values = {
      ...row.toColumns(true),
      if (synced) ...{
        'created_at': Variable<DateTime>(now),
        'updated_at': Variable<DateTime>(now),
        'device_id': Variable<String>(deviceId),
      },
    };

    final inserted = await _db.into(table).insertReturning(_raw(values));
    if (synced) {
      await _log(table, action: action, before: null, after: inserted);
    }
    return inserted;
  });

  /// Updates the row whose primary key is [id] with [changes] and returns it
  /// as stored. Throws if the row does not exist.
  ///
  /// On synced tables, stamps `updated_at` and `device_id`. `updated_at` is
  /// [now], or 1 ms past the stored value when that is not earlier (a second
  /// update in the same call, or a clock set back): the database rejects
  /// updates that leave it unchanged. Never writes `created_at`: [changes]
  /// may not touch it, the primary key or `device_id`.
  ///
  /// [action] overrides the call's action for this row's audit entry.
  Future<D> update<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    String id,
    Insertable<D> changes, {
    String? action,
  }) => _track(() async {
    if (action != null) AuditWriter._checkAction(action);
    final name = _writableName(table);
    final pk = _primaryKey(table);
    final changed = changes.toColumns(true);
    for (final column in {pk.name, 'created_at', 'device_id'}) {
      if (changed.containsKey(column)) {
        throw ArgumentError('$name.$column cannot be changed by an update');
      }
    }
    if (changed.isEmpty) throw ArgumentError('No changes for $name $id');

    Future<D?> read() =>
        (_db.select(table)..where((_) => pk.equals(id))).getSingleOrNull();

    final before = await read();
    if (before == null) throw StateError('$name $id not found');

    final synced = !_localOnlyTables.contains(name);
    var values = changed;
    if (synced) {
      final old = DateTime.parse(_json(before)['updated_at']! as String);
      values = {
        ...changed,
        'updated_at': Variable<DateTime>(
          now.isAfter(old) ? now : old.add(const Duration(milliseconds: 1)),
        ),
        'device_id': Variable<String>(deviceId),
      };
    }
    await (_db.update(table)..where((_) => pk.equals(id))).write(_raw(values));
    final after = (await read())!;
    if (synced) {
      await _log(table, action: action, before: before, after: after);
    }
    return after;
  });

  /// Runs [op] unless the call has returned, and keeps it so writeWithAudit
  /// awaits it even if the body did not.
  Future<R> _track<R>(Future<R> Function() op) {
    if (_closed) {
      throw StateError('AuditedWrites used after writeWithAudit returned');
    }
    final future = op();
    _pending.add(future..ignore());
    return future;
  }

  /// Queues the business row, then writes and queues its audit row.
  ///
  /// The outbox gets the full row. The audit JSON is redacted and, on update,
  /// holds only the columns that changed.
  Future<void> _log(
    TableInfo table, {
    required String? action,
    required DataClass? before,
    required DataClass after,
  }) async {
    final name = table.actualTableName;
    final afterRow = _json(after);
    final id = afterRow[_primaryKey(table).name]! as String;
    await _enqueue(name, id, jsonEncode(afterRow));

    Map<String, Object?>? auditBefore;
    var auditAfter = afterRow;
    if (before != null) {
      final beforeRow = _json(before);
      final changedKeys = [
        for (final k in afterRow.keys)
          if (beforeRow[k] != afterRow[k]) k,
      ];
      auditBefore = {for (final k in changedKeys) k: beforeRow[k]};
      auditAfter = {for (final k in changedKeys) k: afterRow[k]};
    }
    await _audit(
      action: action ?? _action,
      entity: name,
      entityId: id,
      beforeJson: auditBefore == null
          ? null
          : jsonEncode(_redact(name, auditBefore)),
      afterJson: jsonEncode(_redact(name, auditAfter)),
    );
    _writes++;
  }

  Future<void> _audit({
    String? action,
    required String entity,
    required String entityId,
    required String? beforeJson,
    required String afterJson,
  }) async {
    final row = await _db
        .into(_db.auditLog)
        .insertReturning(
          AuditLogCompanion.insert(
            id: Value(newId()),
            createdAt: Value(now),
            updatedAt: Value(now),
            deviceId: Value(deviceId),
            at: now,
            operationId: operationId,
            userId: Value(_userId),
            action: action ?? _action,
            entity: entity,
            entityId: entityId,
            beforeJson: Value(beforeJson),
            afterJson: afterJson,
          ),
        );
    await _enqueue('audit_log', row.id, jsonEncode(_json(row)));
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

  /// Column values for drift. Typed `Never` because `D` can be inferred
  /// wider than the table's row type (e.g. `unawaited(w.insert(...))` infers
  /// `DataClass`), and drift checks the insertable's type at runtime;
  /// `Insertable<Never>` fits every table.
  static Insertable<Never> _raw(Map<String, Expression> values) =>
      RawValuesInsertable<Never>(values);

  static Map<String, Object?> _json(DataClass row) =>
      row.toJson(serializer: auditJsonSerializer);

  static Map<String, Object?> _redact(String table, Map<String, Object?> json) {
    final hidden = _redactedColumns[table] ?? const {};
    final masked = _maskedColumns[table] ?? const {};
    if (hidden.isEmpty && masked.isEmpty) return json;
    return {
      for (final MapEntry(:key, :value) in json.entries)
        key: switch (value) {
          null => null,
          _ when hidden.contains(key) => _redacted,
          final String text when masked.containsKey(key) => masked[key]!(text),
          _ => value,
        },
    };
  }

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

@Riverpod(keepAlive: true)
AuditWriter auditWriter(Ref ref) =>
    AuditWriter(ref.watch(appDatabaseProvider), ref.watch(clockProvider));
