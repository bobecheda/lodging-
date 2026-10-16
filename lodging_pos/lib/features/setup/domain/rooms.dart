/// Rooms and beds (AD-2): models and rules. Pure Dart.
library;

enum BedLabel {
  a('A'),
  b('B');

  const BedLabel(this.code);

  /// As stored in `beds.label`.
  final String code;

  static BedLabel parse(String code) =>
      values.firstWhere((l) => l.code == code);
}

enum Cleanliness {
  clean('clean'),
  notCleaned('not_cleaned');

  const Cleanliness(this.code);

  /// As stored in `beds.cleanliness`.
  final String code;

  static Cleanliness parse(String code) =>
      values.firstWhere((c) => c.code == code);
}

class BedSummary {
  const BedSummary({
    required this.id,
    required this.label,
    required this.categoryId,
    required this.categoryName,
    required this.pricePerNight,
    required this.cleanliness,
    required this.isActive,
    required this.hasActiveStay,
  });

  final String id;
  final BedLabel label;
  final String categoryId;
  final String categoryName;

  /// Current category price, whole KES. A stay keeps the price it locked in.
  final int pricePerNight;
  final Cleanliness cleanliness;
  final bool isActive;
  final bool hasActiveStay;
}

class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.number,
    required this.floor,
    required this.notes,
    required this.isActive,
    required this.beds,
  });

  final String id;
  final String number;
  final String? floor;
  final String? notes;

  /// Inactive rooms are "closed for repairs" and leave the bed board.
  final bool isActive;

  /// Ordered A, B.
  final List<BedSummary> beds;

  Iterable<BedSummary> get activeBeds => beds.where((b) => b.isActive);
}

/// A new room with bed A and optionally bed B.
class NewRoom {
  const NewRoom({
    required this.number,
    required this.floor,
    required this.notes,
    required this.bedACategoryId,
    required this.bedBCategoryId,
  });

  final String number;
  final String? floor;
  final String? notes;
  final String bedACategoryId;
  final String? bedBCategoryId;
}

enum RoomField { number, bedA, bedB }

/// Room numbers are stored trimmed and uppercase (the database CHECKs it),
/// so "3a" and "3A" are the same room.
String normalizeRoomNumber(String input) => input.trim().toUpperCase();

final _roomNumberPattern = RegExp(r'^[A-Z0-9-]{1,10}$');

/// Null if valid. Checks the normalized form.
String? roomNumberError(String input) {
  final number = normalizeRoomNumber(input);
  if (number.isEmpty) return 'Enter the room number';
  if (!_roomNumberPattern.hasMatch(number)) {
    return 'Up to 10 letters, digits or dashes, e.g. 12 or 3A';
  }
  return null;
}

/// Natural order: numeric parts compare as numbers, so 2 comes before 10.
int compareRoomNumbers(String a, String b) {
  final digits = RegExp(r'^\d+');
  final na = digits.firstMatch(a)?.group(0);
  final nb = digits.firstMatch(b)?.group(0);
  if (na != null && nb != null) {
    final byNumber = int.parse(na).compareTo(int.parse(nb));
    if (byNumber != 0) return byNumber;
  } else if (na != null || nb != null) {
    return na != null ? -1 : 1; // numbered rooms first
  }
  return a.compareTo(b);
}

/// Errors per field; empty if the room can be created.
Map<RoomField, String> validateNewRoom(
  NewRoom room, {
  required Set<String> activeCategoryIds,
}) => {
  RoomField.number: ?roomNumberError(room.number),
  if (!activeCategoryIds.contains(room.bedACategoryId))
    RoomField.bedA: 'Choose an active category',
  if (room.bedBCategoryId case final b? when !activeCategoryIds.contains(b))
    RoomField.bedB: 'Choose an active category',
};

String _guestsMessage(List<BedSummary> beds) => beds.length == 1
    ? 'Bed ${beds.single.label.code} has a guest right now. '
          'Check them out first.'
    : 'Beds ${beds.map((b) => b.label.code).join(' and ')} have guests '
          'right now. Check them out first.';

/// Why [bed] can't be deactivated, or null if it can.
String? deactivateBedBlocker(BedSummary bed, RoomSummary room) {
  if (!bed.isActive) return 'This bed is already closed.';
  if (bed.hasActiveStay) return _guestsMessage([bed]);
  // An active room always keeps 1 or 2 active beds.
  if (room.isActive && room.activeBeds.length == 1) {
    return 'Deactivate the room instead.';
  }
  return null;
}

/// Why [room] can't be deactivated, or null if it can.
String? deactivateRoomBlocker(RoomSummary room) {
  if (!room.isActive) return 'This room is already closed.';
  final occupied = room.beds.where((b) => b.hasActiveStay).toList();
  return occupied.isEmpty ? null : _guestsMessage(occupied);
}

/// Why [room] can't be reopened, or null if it can.
String? reactivateRoomBlocker(RoomSummary room) {
  if (room.isActive) return 'This room is already open.';
  if (room.activeBeds.isEmpty) return 'Reactivate a bed first.';
  return null;
}

/// Why [room] can't get a bed B, or null if it can. Labels are A and B only
/// and unique per room, so a closed bed B is reactivated, never replaced.
String? addBedBlocker(RoomSummary room) {
  final b = room.beds.where((bed) => bed.label == BedLabel.b).firstOrNull;
  if (b == null) return null;
  return b.isActive
      ? 'This room already has beds A and B.'
      : 'Bed B is closed. Reactivate it instead.';
}

/// A rule blocked the change; [message] says why and what to do.
class RoomRuleViolation implements Exception {
  const RoomRuleViolation(this.message);
  final String message;

  @override
  String toString() => message;
}

class RoomNumberTaken extends RoomRuleViolation {
  RoomNumberTaken(String number)
    : super('Room $number already exists. Choose another number.');
}

/// The room form has errors; nothing was saved.
class InvalidRoom implements Exception {
  const InvalidRoom(this.errors);
  final Map<RoomField, String> errors;

  @override
  String toString() => errors.values.join(' ');
}

/// Edits from the "Edit room" form: the room's fields plus each existing
/// bed's category. Saved as one operation.
class RoomEdit {
  const RoomEdit({
    required this.number,
    required this.floor,
    required this.notes,
    this.bedCategories = const {},
  });

  final String number;
  final String? floor;
  final String? notes;

  /// New category per existing bed; beds not listed keep theirs.
  final Map<BedLabel, String> bedCategories;
}
