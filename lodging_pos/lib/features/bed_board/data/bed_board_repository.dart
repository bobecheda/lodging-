import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../setup/domain/prices_settings.dart';
import '../../setup/domain/rooms.dart';
import '../domain/bed_board.dart';

/// Reads the bed board (FD-2). Both streams are drift `watch()` queries:
/// check-ins, checkouts, cleaning and setup changes show at once.
class BedBoardRepository {
  BedBoardRepository(this._db);

  final AppDatabase _db;

  /// Open rooms with their active beds, each bed with its category and, if
  /// let, the active stay's guest and paid_until.
  Stream<List<BoardRoom>> watchBoard() {
    final query =
        _db.select(_db.rooms).join([
            innerJoin(
              _db.beds,
              _db.beds.roomId.equalsExp(_db.rooms.id) &
                  _db.beds.isActive.equals(true),
            ),
            innerJoin(
              _db.bedCategories,
              _db.bedCategories.id.equalsExp(_db.beds.categoryId),
            ),
            leftOuterJoin(
              _db.stays,
              _db.stays.bedId.equalsExp(_db.beds.id) &
                  _db.stays.status.equals('active'),
            ),
            leftOuterJoin(
              _db.guests,
              _db.guests.id.equalsExp(_db.stays.guestId),
            ),
          ])
          ..where(_db.rooms.isActive.equals(true))
          ..orderBy([OrderingTerm.asc(_db.beds.label)]);

    return query.watch().map((rows) {
      final rooms = <String, (RoomRow, List<BoardBed>)>{};
      for (final row in rows) {
        final room = row.readTable(_db.rooms);
        final bed = row.readTable(_db.beds);
        final category = row.readTable(_db.bedCategories);
        final stay = row.readTableOrNull(_db.stays);
        final guest = row.readTableOrNull(_db.guests);
        rooms
            .putIfAbsent(room.id, () => (room, <BoardBed>[]))
            .$2
            .add(
              BoardBed(
                id: bed.id,
                label: BedLabel.parse(bed.label),
                categoryId: category.id,
                categoryName: category.name,
                pricePerNight: category.pricePerNight,
                cleanliness: Cleanliness.parse(bed.cleanliness),
                stay: stay == null || guest == null
                    ? null
                    : BoardStay(
                        stayId: stay.id,
                        guestName: guest.fullName,
                        guestPhone: guest.phone,
                        paidUntil: stay.paidUntil,
                      ),
              ),
            );
      }
      return [
        for (final (room, beds) in rooms.values)
          BoardRoom(id: room.id, number: room.roomNumber, beds: beds),
      ];
    });
  }

  /// The grace minutes setting (BR-6), watched so a change in Prices &
  /// settings applies to the board at once.
  Stream<int> watchGraceMinutes() =>
      (_db.select(_db.settings)
            ..where((s) => s.key.equals(SettingKeys.graceMinutes)))
          .watchSingleOrNull()
          .map((row) => graceMinutesFrom(row?.value));
}
