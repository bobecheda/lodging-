/// Housekeeping (FD-9): who cleans which bed, and the rules around it.
/// Pure Dart.
///
/// A task is open until it's completed (the bed becomes clean: the only way
/// it does, BR-9) or cancelled because its bed or room was closed (the bed
/// stays not cleaned). At most one open task per bed.
library;

import '../../setup/domain/rooms.dart';

/// An active housekeeper, as the dropdown lists them.
typedef HousekeeperOption = ({String id, String fullName});

String _first(String fullName) => fullName.trim().split(RegExp(r'\s+')).first;

/// What to call each housekeeper on tiles, in messages and the dropdown:
/// the first name, or the full name for anyone whose first name another
/// active housekeeper shares.
Map<String, String> housekeeperNames(Iterable<HousekeeperOption> all) {
  final counts = <String, int>{};
  for (final h in all) {
    final key = _first(h.fullName).toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return {
    for (final h in all)
      h.id: counts[_first(h.fullName).toLowerCase()]! > 1
          ? h.fullName
          : _first(h.fullName),
  };
}

/// The To clean tile's second line: `Needs cleaning · assign`, or
/// `Needs cleaning · Rose` once someone has it.
String cleaningLine(String? assignee) =>
    'Needs cleaning · ${assignee ?? 'assign'}';

/// A room shows Not cleaned while any of its (active) beds is.
bool roomNeedsCleaning(Iterable<Cleanliness> beds) =>
    beds.any((c) => c == Cleanliness.notCleaned);

/// Why a bed can't be given to a housekeeper now, or null if it can.
String? assignBlocker({
  required Cleanliness cleanliness,
  required bool hasOpenTask,
  required bool housekeeperActive,
}) {
  if (cleanliness == Cleanliness.clean) return 'This bed is already clean.';
  if (hasOpenTask) {
    return 'Someone is already cleaning this bed. Reassign it instead.';
  }
  if (!housekeeperActive) {
    return 'That housekeeper is no longer active. Choose another.';
  }
  return null;
}

/// Why [fullName] can't be deactivated while [openTasks] beds wait for
/// them, or null if they can (FD-9, AD-4).
String? housekeeperDeactivateBlocker(String fullName, int openTasks) {
  if (openTasks == 0) return null;
  final name = _first(fullName);
  return openTasks == 1
      ? '$name has a bed to clean. Finish or reassign it first.'
      : '$name has $openTasks beds to clean. Finish or reassign them first.';
}
