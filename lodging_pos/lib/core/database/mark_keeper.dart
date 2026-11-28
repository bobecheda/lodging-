import '../clock/clock.dart';
import 'database.dart';
import 'desk_startup.dart';

/// Moves the high-water mark with the work (story/desk-db-guards-2): after
/// every committed operation in [markActions] (a receipt number issued, a
/// shift opened or closed, a drawer count), both copies of the mark are
/// raised to what the live database now holds. Wired to
/// [AuditWriter.onCommitted] on the real desk.
class MarkKeeper {
  MarkKeeper(this._db, this._marks, this._clock);

  final AppDatabase _db;
  final MarkStore _marks;
  final Clock _clock;

  Future<void> afterCommit(Set<String> actions) async {
    if (!movesMark(actions)) return;
    await _marks.raise(await liveFigures(_db), at: _clock.now());
  }
}

/// The open database's figures, counted as the startup check counts the
/// file ([figuresOf]).
Future<DatabaseFigures> liveFigures(AppDatabase db) => figuresOf(
  (query) async =>
      (await db.customSelect(query).getSingleOrNull())?.data.values.first,
  schema: 'main',
);
