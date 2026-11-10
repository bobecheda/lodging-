/// The cash drawer as one running ledger across shifts (FD-11, Story B).
/// Pure Dart.
///
/// UB40 has one drawer and one receptionist; cash stays in the drawer
/// between shifts and the float is whatever is left. The desk has one open
/// shift at a time, so every shift, a supervisor's too, is a link in one
/// chain:
///
/// - **Anchors** are counts: the starting cash (counted by the supervisor or
///   owner before the first shift), every closing count, and (Story B2)
///   every drawer check and collection.
/// - A shift's **opening float** is the latest anchor's balance: never typed,
///   never shown to the receptionist.
/// - A float that isn't the count before it is a **break** in the chain (only
///   an edited database, or shifts from before the chain, have one).
library;

import '../../../core/money/kes.dart';
import 'shift_close.dart' as close;

enum AnchorKind { start, close, check, collect }

/// A count the drawer's balance starts again from.
final class DrawerAnchor {
  const DrawerAnchor({
    required this.id,
    required this.kind,
    required this.at,
    required this.counted,
    this.removed = 0,
  });

  /// The shift's id for a close, else the drawer event's.
  final String id;
  final AnchorKind kind;

  /// UTC.
  final DateTime at;
  final int counted;

  /// Cash taken away at a collection (Story B2).
  final int removed;

  /// What the drawer holds after it.
  int get balance => counted - removed;
}

/// The latest of [anchors] (a later one wins a tie), or null before the
/// starting cash is counted.
DrawerAnchor? openingFloatFrom(Iterable<DrawerAnchor> anchors) {
  DrawerAnchor? latest;
  for (final a in anchors) {
    if (latest == null || !a.at.isBefore(latest.at)) latest = a;
  }
  return latest;
}

/// What the drawer should hold now: the last count between shifts, or
/// during a shift its float plus its net cash. Null before any count.
int? drawerExpectedNow({
  required int? latest,
  int? openFloat,
  int openCashNet = 0,
}) => openFloat != null ? openFloat + openCashNet : latest;

// ── The chain ────────────────────────────────────────────────────────────

/// A shift as the chain reads it.
final class ChainShift {
  const ChainShift({
    required this.id,
    required this.userName,
    required this.openedAt,
    required this.openingFloat,
    this.closedAt,
    this.expectedCash,
    this.firstCount,
    this.counted,
    this.needsReview = false,
    this.note,
  });

  final String id;
  final String userName;
  final DateTime openedAt;
  final int openingFloat;

  // Set once closed.
  final DateTime? closedAt;
  final int? expectedCash;
  final int? firstCount;
  final int? counted;
  final bool needsReview;
  final String? note;
}

/// The starting cash, as counted by the supervisor or owner.
final class DrawerStartRecord {
  const DrawerStartRecord({
    required this.id,
    required this.at,
    required this.counted,
    required this.by,
  });

  final String id;
  final DateTime at;
  final int counted;

  /// The counter's full name.
  final String by;
}

/// One step of the chain, for the Cash screen.
sealed class ChainEntry {
  const ChainEntry(this.at);

  /// UTC.
  final DateTime at;
  String get title;
  String get detail;
}

final class DrawerStarted extends ChainEntry {
  const DrawerStarted(super.at, {required this.counted, required this.by});

  final int counted;
  final String by;

  @override
  String get title => 'Starting cash counted';

  @override
  String get detail => '${formatKes(counted)} · by $by';
}

final class ShiftOpenedEntry extends ChainEntry {
  const ShiftOpenedEntry(
    super.at, {
    required this.shiftId,
    required this.userName,
    required this.float,
    required this.anchorBalance,
  });

  final String shiftId;
  final String userName;
  final int float;

  /// The balance of the count before it; null when there was none.
  final int? anchorBalance;

  bool get isBreak => anchorBalance != float;

  @override
  String get title => '$userName opened a shift';

  @override
  String get detail => switch (anchorBalance) {
    null => 'Float ${formatKes(float)}, with no count before it',
    final b when b != float =>
      'Float ${formatKes(float)}, but the drawer should hold ${formatKes(b)}',
    _ => 'Float ${formatKes(float)}',
  };
}

final class ShiftClosedEntry extends ChainEntry {
  const ShiftClosedEntry(
    super.at, {
    required this.shiftId,
    required this.userName,
    required this.expected,
    required this.firstCount,
    required this.counted,
    required this.needsReview,
    this.note,
  });

  final String shiftId;
  final String userName;
  final int expected;
  final int firstCount;
  final int counted;
  final bool needsReview;
  final String? note;

  /// Counted − expected: negative is short.
  int get gap => counted - expected;

  bool get matchedOnRecount => close.matchedOnRecount(
    firstCount: firstCount,
    counted: counted,
    needsReview: needsReview,
  );

  @override
  String get title => '$userName closed the shift';

  @override
  String get detail =>
      'Expected ${formatKes(expected)} · counted ${formatKes(counted)} · '
      '${close.varianceLabel(gap)}';
}

/// The drawer's history, newest first: the starting cash, then each
/// shift's opening (checked against the count before it) and close.
List<ChainEntry> drawerChain({
  required List<ChainShift> shifts,
  required List<DrawerStartRecord> starts,
}) {
  final anchors = [
    for (final s in starts)
      DrawerAnchor(
        id: s.id,
        kind: AnchorKind.start,
        at: s.at,
        counted: s.counted,
      ),
    for (final s in shifts)
      if (s.closedAt != null)
        DrawerAnchor(
          id: s.id,
          kind: AnchorKind.close,
          at: s.closedAt!,
          counted: s.counted!,
        ),
  ];
  final entries = <ChainEntry>[
    for (final s in starts) DrawerStarted(s.at, counted: s.counted, by: s.by),
    for (final s in shifts) ...[
      ShiftOpenedEntry(
        s.openedAt,
        shiftId: s.id,
        userName: s.userName,
        float: s.openingFloat,
        anchorBalance: openingFloatFrom([
          for (final a in anchors)
            if (a.id != s.id && !a.at.isAfter(s.openedAt)) a,
        ])?.balance,
      ),
      if (s.closedAt case final closedAt?)
        ShiftClosedEntry(
          closedAt,
          shiftId: s.id,
          userName: s.userName,
          expected: s.expectedCash!,
          firstCount: s.firstCount!,
          counted: s.counted!,
          needsReview: s.needsReview,
          note: s.note,
        ),
    ],
  ];
  // Newest first; at the same moment a close comes after its opening and
  // the starting cash before the first opening.
  int rank(ChainEntry e) => switch (e) {
    DrawerStarted() => 0,
    ShiftOpenedEntry() => 1,
    ShiftClosedEntry() => 2,
  };
  entries.sort((a, b) {
    final byTime = b.at.compareTo(a.at);
    return byTime != 0 ? byTime : rank(b) - rank(a);
  });
  return entries;
}
