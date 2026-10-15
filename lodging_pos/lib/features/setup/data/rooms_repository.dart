import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/admin_guard.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../domain/bed_category.dart';
import '../domain/rooms.dart';

/// Rooms and beds (AD-2). Owner only: every write takes the acting user and
/// throws [AdminOnly] for anyone else. Rooms and beds are deactivated, never
/// deleted; every rule check runs inside the write's transaction.
class RoomsRepository {
  RoomsRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditWriter _audit;

  /// All rooms, naturally sorted by number, each with its beds (A, B).
  Future<List<RoomSummary>> rooms() => _load();

  Future<RoomSummary> room(String roomId) async =>
      (await _load(roomId: roomId)).single;

  /// Categories for the bed selects, in sort order.
  Future<List<BedCategory>> categories() async {
    final rows = await (_db.select(
      _db.bedCategories,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
    return [
      for (final c in rows)
        BedCategory(
          id: c.id,
          name: c.name,
          pricePerBlock: c.pricePerBlock,
          sortOrder: c.sortOrder,
          isActive: c.isActive,
        ),
    ];
  }

  /// Creates a room with bed A and optionally bed B, both clean:
  /// `room.create` + `bed.create` per bed, one operation.
  Future<RoomSummary> createRoom(UserAccount admin, NewRoom input) async {
    requireAdmin(admin);
    final roomId = await _audit.writeWithAudit(
      action: 'room.create',
      userId: admin.id,
      body: (w) async {
        final errors = validateNewRoom(
          input,
          activeCategoryIds: await _activeCategoryIds(),
        );
        if (errors.isNotEmpty) throw InvalidRoom(errors);
        final number = normalizeRoomNumber(input.number);
        await _requireFreeNumber(number);

        final room = await w.insert(
          _db.rooms,
          RoomsCompanion.insert(
            roomNumber: number,
            floor: Value(_optional(input.floor)),
            notes: Value(_optional(input.notes)),
          ),
        );
        for (final (label, categoryId) in [
          (BedLabel.a, input.bedACategoryId),
          if (input.bedBCategoryId case final b?) (BedLabel.b, b),
        ]) {
          await w.insert(
            _db.beds,
            _newBed(room.id, label, categoryId),
            action: 'bed.create',
          );
        }
        return room.id;
      },
    );
    return room(roomId);
  }

  /// Saves the "Edit room" form: `room.update` for the room's own fields and
  /// `bed.update` per bed whose category changed, one operation. A category
  /// change affects new check-ins only: stays keep the price they locked.
  Future<RoomSummary> updateRoom(
    UserAccount admin,
    String roomId,
    RoomEdit edit,
  ) async {
    requireAdmin(admin);
    final numberProblem = roomNumberError(edit.number);
    if (numberProblem != null) {
      throw InvalidRoom({RoomField.number: numberProblem});
    }
    final number = normalizeRoomNumber(edit.number);
    final floor = _optional(edit.floor);
    final notes = _optional(edit.notes);

    final before = await room(roomId);
    final roomChanged =
        number != before.number ||
        floor != before.floor ||
        notes != before.notes;
    final bedChanges = {
      for (final bed in before.beds)
        if (edit.bedCategories[bed.label] case final c?
            when c != bed.categoryId)
          bed: c,
    };
    if (!roomChanged && bedChanges.isEmpty) return before;

    await _audit.writeWithAudit(
      action: 'room.update',
      userId: admin.id,
      body: (w) async {
        if (roomChanged) {
          if (number != before.number) await _requireFreeNumber(number);
          await w.update(
            _db.rooms,
            roomId,
            RoomsCompanion(
              roomNumber: Value(number),
              floor: Value(floor),
              notes: Value(notes),
            ),
          );
        }
        final active = await _activeCategoryIds();
        for (final MapEntry(key: bed, value: categoryId)
            in bedChanges.entries) {
          if (!active.contains(categoryId)) {
            throw InvalidRoom({
              bed.label == BedLabel.a ? RoomField.bedA : RoomField.bedB:
                  'Choose an active category',
            });
          }
          await w.update(
            _db.beds,
            bed.id,
            BedsCompanion(categoryId: Value(categoryId)),
            action: 'bed.update',
          );
        }
      },
    );
    return room(roomId);
  }

  /// Adds bed B (clean) to a room that has only bed A (`bed.create`).
  Future<RoomSummary> addBed(
    UserAccount admin,
    String roomId,
    String categoryId,
  ) async {
    requireAdmin(admin);
    await _audit.writeWithAudit(
      action: 'bed.create',
      userId: admin.id,
      body: (w) async {
        _block(addBedBlocker(await room(roomId)));
        if (!(await _activeCategoryIds()).contains(categoryId)) {
          throw const InvalidRoom({
            RoomField.bedB: 'Choose an active category',
          });
        }
        await w.insert(_db.beds, _newBed(roomId, BedLabel.b, categoryId));
      },
    );
    return room(roomId);
  }

  /// Closes a bed for repairs (`bed.deactivate`). Blocked while it has a
  /// guest, or when it is an open room's last active bed.
  Future<RoomSummary> deactivateBed(UserAccount admin, String bedId) async {
    requireAdmin(admin);
    final roomId = await _roomIdOf(bedId);
    await _audit.writeWithAudit(
      action: 'bed.deactivate',
      userId: admin.id,
      body: (w) async {
        final current = await room(roomId);
        final bed = current.beds.firstWhere((b) => b.id == bedId);
        _block(deactivateBedBlocker(bed, current));
        await w.update(
          _db.beds,
          bedId,
          const BedsCompanion(isActive: Value(false)),
        );
      },
    );
    return room(roomId);
  }

  /// Reopens a bed after repairs (`bed.reactivate`). It comes back
  /// `not_cleaned`, so cleaning is assigned before the first guest.
  Future<RoomSummary> reactivateBed(UserAccount admin, String bedId) async {
    requireAdmin(admin);
    final roomId = await _roomIdOf(bedId);
    await _audit.writeWithAudit(
      action: 'bed.reactivate',
      userId: admin.id,
      body: (w) async {
        final bed = (await room(roomId)).beds.firstWhere((b) => b.id == bedId);
        if (bed.isActive) {
          throw const RoomRuleViolation('This bed is already open.');
        }
        await w.update(
          _db.beds,
          bedId,
          BedsCompanion(
            isActive: const Value(true),
            cleanliness: Value(Cleanliness.notCleaned.code),
          ),
        );
      },
    );
    return room(roomId);
  }

  /// Closes a room for repairs (`room.deactivate`); it leaves the bed board.
  /// Blocked while any of its beds has a guest.
  Future<RoomSummary> deactivateRoom(UserAccount admin, String roomId) async {
    requireAdmin(admin);
    await _audit.writeWithAudit(
      action: 'room.deactivate',
      userId: admin.id,
      body: (w) async {
        _block(deactivateRoomBlocker(await room(roomId)));
        await w.update(
          _db.rooms,
          roomId,
          const RoomsCompanion(isActive: Value(false)),
        );
      },
    );
    return room(roomId);
  }

  /// Reopens a room after repairs (`room.reactivate`). Its active beds come
  /// back `not_cleaned`, recorded in the same operation.
  Future<RoomSummary> reactivateRoom(UserAccount admin, String roomId) async {
    requireAdmin(admin);
    await _audit.writeWithAudit(
      action: 'room.reactivate',
      userId: admin.id,
      body: (w) async {
        final current = await room(roomId);
        _block(reactivateRoomBlocker(current));
        await w.update(
          _db.rooms,
          roomId,
          const RoomsCompanion(isActive: Value(true)),
        );
        for (final bed in current.activeBeds) {
          if (bed.cleanliness == Cleanliness.notCleaned) continue;
          await w.update(
            _db.beds,
            bed.id,
            BedsCompanion(cleanliness: Value(Cleanliness.notCleaned.code)),
          );
        }
      },
    );
    return room(roomId);
  }

  // --- helpers ---

  Future<List<RoomSummary>> _load({String? roomId}) async {
    final roomRows =
        await (_db.select(_db.rooms)..where(
              (r) =>
                  roomId == null ? const Constant(true) : r.id.equals(roomId),
            ))
            .get();
    if (roomRows.isEmpty && roomId != null) {
      throw RoomRuleViolation('Room not found.');
    }

    final bedQuery = _db.select(_db.beds).join([
      innerJoin(
        _db.bedCategories,
        _db.bedCategories.id.equalsExp(_db.beds.categoryId),
      ),
    ]);
    if (roomId != null) bedQuery.where(_db.beds.roomId.equals(roomId));
    final bedRows = await bedQuery.get();

    final occupied =
        await (_db.selectOnly(_db.stays)
              ..addColumns([_db.stays.bedId])
              ..where(_db.stays.status.equals('active')))
            .map((r) => r.read(_db.stays.bedId)!)
            .get();
    final occupiedBeds = occupied.toSet();

    final bedsByRoom = <String, List<BedSummary>>{};
    for (final row in bedRows) {
      final bed = row.readTable(_db.beds);
      final category = row.readTable(_db.bedCategories);
      bedsByRoom
          .putIfAbsent(bed.roomId, () => [])
          .add(
            BedSummary(
              id: bed.id,
              label: BedLabel.parse(bed.label),
              categoryId: category.id,
              categoryName: category.name,
              pricePerBlock: category.pricePerBlock,
              cleanliness: Cleanliness.parse(bed.cleanliness),
              isActive: bed.isActive,
              hasActiveStay: occupiedBeds.contains(bed.id),
            ),
          );
    }

    return [
      for (final r in roomRows)
        RoomSummary(
          id: r.id,
          number: r.roomNumber,
          floor: r.floor,
          notes: r.notes,
          isActive: r.isActive,
          beds: (bedsByRoom[r.id] ?? [])
            ..sort((a, b) => a.label.index.compareTo(b.label.index)),
        ),
    ]..sort((a, b) => compareRoomNumbers(a.number, b.number));
  }

  Future<Set<String>> _activeCategoryIds() async => {
    for (final c in await (_db.select(
      _db.bedCategories,
    )..where((c) => c.isActive)).get())
      c.id,
  };

  Future<void> _requireFreeNumber(String number) async {
    final taken = await (_db.select(
      _db.rooms,
    )..where((r) => r.roomNumber.equals(number))).getSingleOrNull();
    if (taken != null) throw RoomNumberTaken(number);
  }

  Future<String> _roomIdOf(String bedId) async {
    final bed = await (_db.select(
      _db.beds,
    )..where((b) => b.id.equals(bedId))).getSingleOrNull();
    if (bed == null) throw const RoomRuleViolation('Bed not found.');
    return bed.roomId;
  }

  static BedsCompanion _newBed(
    String roomId,
    BedLabel label,
    String categoryId,
  ) => BedsCompanion.insert(
    roomId: roomId,
    label: label.code,
    categoryId: categoryId,
    cleanliness: Cleanliness.clean.code,
  );

  static void _block(String? reason) {
    if (reason != null) throw RoomRuleViolation(reason);
  }

  static String? _optional(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
