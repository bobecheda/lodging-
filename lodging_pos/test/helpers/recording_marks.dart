import 'package:lodging_pos/core/database/desk_startup.dart';

/// A [MarkStore] that keeps what it was given (story/desk-db-guards-2).
class RecordingMarks implements MarkStore {
  RecordingMarks({this.fail = false});

  /// Every write throws, as a locked file would.
  final bool fail;

  final raised =
      <({DatabaseFigures figures, DateTime at, String? backupName})>[];
  final replaced = <HighWaterMark>[];

  @override
  Future<void> raise(
    DatabaseFigures figures, {
    required DateTime at,
    String? backupName,
  }) async {
    if (fail) throw StateError('locked');
    raised.add((figures: figures, at: at, backupName: backupName));
  }

  @override
  Future<void> replace(HighWaterMark mark) async {
    if (fail) throw StateError('locked');
    replaced.add(mark);
  }
}
