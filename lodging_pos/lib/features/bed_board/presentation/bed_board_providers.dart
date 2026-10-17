import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/clock/clock.dart';
import '../../../core/database/database_provider.dart';
import '../data/bed_board_repository.dart';
import '../domain/bed_board.dart';

part 'bed_board_providers.g.dart';

@Riverpod(keepAlive: true)
BedBoardRepository bedBoardRepository(Ref ref) =>
    BedBoardRepository(ref.watch(appDatabaseProvider));

/// Open rooms and their active beds, watched (drift `watch()`).
@riverpod
Stream<List<BoardRoom>> boardRooms(Ref ref) =>
    ref.watch(bedBoardRepositoryProvider).watchBoard();

/// The grace setting, watched.
@riverpod
Stream<int> boardGraceMinutes(Ref ref) =>
    ref.watch(bedBoardRepositoryProvider).watchGraceMinutes();

/// How often the board re-reads the clock, so a bed turns Overstay on its
/// own (FD-7). Null in tests: no timer, the clock is set by hand.
@Riverpod(keepAlive: true)
Duration? boardTickInterval(Ref ref) => const Duration(seconds: 30);

/// "Now" for the board: once at once, then every [boardTickInterval]. Ends
/// with the board (auto-dispose), which stops the timer.
@riverpod
Stream<DateTime> boardNow(Ref ref) async* {
  final clock = ref.watch(clockProvider);
  yield clock.now();
  final interval = ref.watch(boardTickIntervalProvider);
  if (interval == null) return;
  yield* Stream.periodic(interval, (_) => clock.now());
}
