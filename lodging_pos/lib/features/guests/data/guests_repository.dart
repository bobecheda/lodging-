import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../domain/guest.dart';

/// The guest form failed [validateGuest], or its ID is already registered.
class InvalidGuest implements Exception {
  const InvalidGuest(this.errors);
  final Map<GuestField, String> errors;
}

const _idTaken = 'This ID is already registered to another guest.';

/// Guests (FD-3). Searching is open to anyone signed in; registering and
/// correcting need [Permission.registerGuests]. Writes go through
/// writeWithAudit (`guest.create`, `guest.update`); the ID check runs inside
/// the transaction, backed by the `guests_id_unique` index.
class GuestsRepository {
  GuestsRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditWriter _audit;

  static const searchLimit = 8;
  static const recentLimit = 30;

  // The lists are drift `watch()` queries: they emit again whenever a guest
  // is registered or corrected, so screens never refresh by hand.

  /// The [recentLimit] guests registered or corrected most recently, newest
  /// first.
  Stream<List<Guest>> watchRecent() =>
      (_db.select(_db.guests)
            ..orderBy([
              (g) => OrderingTerm.desc(g.updatedAt),
              (g) => OrderingTerm.desc(g.createdAt),
            ])
            ..limit(recentLimit))
          .watch()
          .map((rows) => [for (final r in rows) _toGuest(r)]);

  /// Guests whose phone or ID number starts with the query, by name. Both
  /// prefixes use their indexes (`COLLATE NOCASE`).
  Stream<List<Guest>> watchSearch(GuestQuery query) {
    if (query.isEmpty) return Stream.value(const []);
    return _searchQuery(query)
        .watch()
        .map((rows) => [for (final r in rows) _toGuest(r)]);
  }

  /// One-off search (no watching), for code that only needs it once.
  Future<List<Guest>> search(GuestQuery query) async {
    if (query.isEmpty) return const [];
    return [for (final r in await _searchQuery(query).get()) _toGuest(r)];
  }

  SimpleSelectStatement<$GuestsTable, GuestRow> _searchQuery(GuestQuery q) {
    final phone = q.phonePrefix;
    final id = q.idPrefix;
    return _db.select(_db.guests)
      ..where(
        (g) => Expression.or([
          if (phone != null) g.phone.like('$phone%'),
          if (id != null) g.idNumber.like('$id%'),
        ]),
      )
      ..orderBy([(g) => OrderingTerm.asc(g.fullName)])
      ..limit(searchLimit);
  }

  Stream<Guest> watchGuest(String id) => (_db.select(
    _db.guests,
  )..where((g) => g.id.equals(id))).watchSingle().map(_toGuest);

  Future<Guest> guest(String id) async => _toGuest(
    await (_db.select(_db.guests)..where((g) => g.id.equals(id))).getSingle(),
  );

  /// Other guests already registered with [phone] (stored form), so the
  /// form can say so before a duplicate is made.
  Future<List<Guest>> withPhone(String phone, {String? exceptId}) async {
    final rows =
        await (_db.select(_db.guests)..where(
              (g) =>
                  g.phone.equals(phone) &
                  (exceptId == null
                      ? const Constant(true)
                      : g.id.isNotValue(exceptId)),
            ))
            .get();
    return [for (final r in rows) _toGuest(r)];
  }

  /// `guest.create`.
  Future<Guest> register(UserAccount actor, GuestForm input) async {
    requirePermission(actor, Permission.registerGuests);
    final form = _checked(input);
    final row = await _audit.writeWithAudit(
      action: 'guest.create',
      userId: actor.id,
      body: (w) async {
        await _requireFreeId(form);
        return w.insert(
          _db.guests,
          GuestsCompanion.insert(
            fullName: form.fullName,
            phone: form.phone,
            idType: Value(form.idType?.code),
            idNumber: Value(form.idNumber.isEmpty ? null : form.idNumber),
          ),
        );
      },
    );
    return _toGuest(row);
  }

  /// Corrects a guest's name, phone or ID (`guest.update`). Returns false
  /// when nothing changed.
  Future<bool> update(UserAccount actor, String id, GuestForm input) async {
    requirePermission(actor, Permission.registerGuests);
    final form = _checked(input);
    final current = await guest(id);
    final number = form.idNumber.isEmpty ? null : form.idNumber;
    if (current.fullName == form.fullName &&
        current.phone == form.phone &&
        current.idType == form.idType &&
        current.idNumber == number) {
      return false;
    }
    await _audit.writeWithAudit(
      action: 'guest.update',
      userId: actor.id,
      body: (w) async {
        await _requireFreeId(form, exceptId: id);
        await w.update(
          _db.guests,
          id,
          GuestsCompanion(
            fullName: Value(form.fullName),
            phone: Value(form.phone),
            idType: Value(form.idType?.code),
            idNumber: Value(number),
          ),
        );
      },
    );
    return true;
  }

  static GuestForm _checked(GuestForm input) {
    final errors = validateGuest(input);
    if (errors.isNotEmpty) throw InvalidGuest(errors);
    return input.normalized();
  }

  /// The ID (type + number) may belong to one guest only.
  Future<void> _requireFreeId(GuestForm form, {String? exceptId}) async {
    final type = form.idType;
    if (type == null || form.idNumber.isEmpty) return;
    final taken =
        await (_db.select(_db.guests)
              ..where(
                (g) =>
                    g.idType.equals(type.code) &
                    g.idNumber.equals(form.idNumber) &
                    (exceptId == null
                        ? const Constant(true)
                        : g.id.isNotValue(exceptId)),
              )
              ..limit(1))
            .getSingleOrNull();
    if (taken != null) {
      throw const InvalidGuest({GuestField.idNumber: _idTaken});
    }
  }

  static Guest _toGuest(GuestRow r) => Guest(
    id: r.id,
    fullName: r.fullName,
    phone: r.phone,
    idType: r.idType == null ? null : IdType.parse(r.idType!),
    idNumber: r.idNumber,
    registeredAt: r.createdAt,
  );
}
