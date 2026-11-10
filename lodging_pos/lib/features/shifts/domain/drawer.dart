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
import 'shift_close.dart'
    show closeReasonError, countError, countMatches, countAgainMessage;

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

/// Cash in or out of the drawer: + a cash payment, − a cash refund paid
/// out. Voided ones are left out by the caller.
final class CashMove {
  const CashMove({required this.at, required this.amount});

  /// UTC.
  final DateTime at;
  final int amount;
}

/// What the drawer should hold at [at]: [anchor]'s balance plus the cash
/// that moved after it, up to [at] (B2: a check or collection mid-shift is
/// an anchor too, so later cash adds to its count).
int expectedAt({
  required DrawerAnchor anchor,
  required Iterable<CashMove> moves,
  required DateTime at,
}) =>
    anchor.balance +
    moves
        .where((m) => m.at.isAfter(anchor.at) && !m.at.isAfter(at))
        .fold(0, (sum, m) => sum + m.amount);

// ── Drawer checks and collections (B2) ───────────────────────────────────

enum DrawerCountKind {
  check('check'),
  collect('collect');

  const DrawerCountKind(this.code);
  final String code;
}

/// A drawer count's rule refused it; [message] is shown to the counter.
class DrawerCountProblem implements Exception {
  const DrawerCountProblem(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a drawer check or collection records: the counts and whether it
/// needs review.
final class DrawerCount {
  const DrawerCount({
    required this.firstCount,
    required this.counted,
    required this.needsReview,
    this.note,
  });

  final int firstCount;
  final int counted;
  final bool needsReview;
  final String? note;
}

/// A drawer check's or collection's count, blind, as at close: a first
/// count that matches [expected] is recorded; one that doesn't needs one
/// [recount]; a recount that doesn't match needs [note] and is recorded for
/// review. There is never a third count, nor a recount after a match.
DrawerCount drawerCountOf({
  required int expected,
  required int firstCount,
  int? recount,
  String? note,
  int tolerance = 0,
}) {
  if (countError(firstCount) case final p?) throw DrawerCountProblem(p);
  if (recount != null) {
    if (countError(recount) case final p?) throw DrawerCountProblem(p);
  }
  bool matches(int c) =>
      countMatches(c, expected: expected, tolerance: tolerance);
  if (matches(firstCount)) {
    if (recount != null) {
      throw const DrawerCountProblem(
        'The first count matched: there is nothing to recount.',
      );
    }
    return DrawerCount(
      firstCount: firstCount,
      counted: firstCount,
      needsReview: false,
    );
  }
  if (recount == null) throw const DrawerCountProblem(countAgainMessage);
  if (matches(recount)) {
    return DrawerCount(
      firstCount: firstCount,
      counted: recount,
      needsReview: false,
    );
  }
  if (closeReasonError(note ?? '') case final p?) throw DrawerCountProblem(p);
  return DrawerCount(
    firstCount: firstCount,
    counted: recount,
    needsReview: true,
    note: note!.trim(),
  );
}

/// Null if [removed] can be taken away at a collection that counted
/// [counted].
String? removedError(int? removed, {required int counted}) {
  if (removed == null) return 'Enter the cash taken away.';
  if (removed < 0) return 'The amount can’t be negative.';
  if (removed > counted) return 'You can’t take away more than you counted.';
  return null;
}

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

/// A drawer check or collection as the chain reads it.
final class DrawerCountRecord {
  const DrawerCountRecord({
    required this.id,
    required this.kind,
    required this.at,
    required this.expected,
    required this.firstCount,
    required this.counted,
    required this.by,
    required this.present,
    this.removed = 0,
    this.needsReview = false,
    this.note,
  });

  final String id;
  final DrawerCountKind kind;
  final DateTime at;
  final int expected;
  final int firstCount;
  final int counted;

  /// The counter's and the present receptionist's full names.
  final String by;
  final String present;
  final int removed;
  final bool needsReview;
  final String? note;
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

/// A drawer check or a collection, in the chain.
sealed class DrawerCountEntry extends ChainEntry {
  DrawerCountEntry(this.record) : super(record.at);

  final DrawerCountRecord record;

  /// Counted − expected: negative is short.
  int get gap => record.counted - record.expected;
  bool get needsReview => record.needsReview;
  String? get note => record.note;
  bool get matchedOnRecount => close.matchedOnRecount(
    firstCount: record.firstCount,
    counted: record.counted,
    needsReview: record.needsReview,
  );

  String get _counts =>
      'Expected ${formatKes(record.expected)} · counted '
      '${formatKes(record.counted)} · ${close.varianceLabel(gap)}';
}

final class DrawerChecked extends DrawerCountEntry {
  DrawerChecked(super.record);

  @override
  String get title =>
      '${record.by} checked the drawer, ${record.present} present';

  @override
  String get detail => _counts;
}

final class CashCollected extends DrawerCountEntry {
  CashCollected(super.record);

  @override
  String get title => '${record.by} collected cash, ${record.present} present';

  @override
  String get detail =>
      '$_counts · ${formatKes(record.removed)} taken, '
      '${formatKes(record.counted - record.removed)} left';
}

/// What happened between the last collection and the one before it, for
/// the collector's "Show the week's figures".
final class WeekSummary {
  const WeekSummary({
    required this.closes,
    required this.checks,
    required this.reviews,
    required this.recountMatches,
    required this.entries,
  });

  final int closes;
  final int checks;

  /// Closes and checks that need review.
  final int reviews;
  final int recountMatches;

  /// Those entries, newest first.
  final List<ChainEntry> entries;
}

/// The entries between the newest collection in [chain] (newest first) and
/// the one before it (or the start of the chain).
WeekSummary sinceLastCollection(List<ChainEntry> chain) {
  final newest = chain.indexWhere((e) => e is CashCollected);
  final rest = chain.skip(newest + 1).toList();
  final previous = rest.indexWhere((e) => e is CashCollected);
  final week = previous < 0 ? rest : rest.take(previous).toList();
  bool review(ChainEntry e) => switch (e) {
    ShiftClosedEntry(:final needsReview) => needsReview,
    DrawerCountEntry(:final needsReview) => needsReview,
    _ => false,
  };
  bool onRecount(ChainEntry e) => switch (e) {
    ShiftClosedEntry(:final matchedOnRecount) => matchedOnRecount,
    DrawerCountEntry(:final matchedOnRecount) => matchedOnRecount,
    _ => false,
  };
  return WeekSummary(
    closes: week.whereType<ShiftClosedEntry>().length,
    checks: week.whereType<DrawerChecked>().length,
    reviews: week.where(review).length,
    recountMatches: week.where(onRecount).length,
    entries: week,
  );
}

/// The drawer's history, newest first: the starting cash, then each
/// shift's opening (checked against the count before it) and close, and
/// (B2) every drawer check and collection.
List<ChainEntry> drawerChain({
  required List<ChainShift> shifts,
  required List<DrawerStartRecord> starts,
  List<DrawerCountRecord> counts = const [],
}) {
  final anchors = [
    for (final s in starts)
      DrawerAnchor(
        id: s.id,
        kind: AnchorKind.start,
        at: s.at,
        counted: s.counted,
      ),
    for (final c in counts)
      DrawerAnchor(
        id: c.id,
        kind: c.kind == DrawerCountKind.check
            ? AnchorKind.check
            : AnchorKind.collect,
        at: c.at,
        counted: c.counted,
        removed: c.removed,
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
    for (final c in counts)
      c.kind == DrawerCountKind.check ? DrawerChecked(c) : CashCollected(c),
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
    DrawerCountEntry() => 2,
    ShiftClosedEntry() => 3,
  };
  entries.sort((a, b) {
    final byTime = b.at.compareTo(a.at);
    return byTime != 0 ? byTime : rank(b) - rank(a);
  });
  return entries;
}
