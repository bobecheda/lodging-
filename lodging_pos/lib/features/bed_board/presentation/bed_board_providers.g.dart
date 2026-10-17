// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bed_board_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bedBoardRepository)
final bedBoardRepositoryProvider = BedBoardRepositoryProvider._();

final class BedBoardRepositoryProvider
    extends
        $FunctionalProvider<
          BedBoardRepository,
          BedBoardRepository,
          BedBoardRepository
        >
    with $Provider<BedBoardRepository> {
  BedBoardRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bedBoardRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bedBoardRepositoryHash();

  @$internal
  @override
  $ProviderElement<BedBoardRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BedBoardRepository create(Ref ref) {
    return bedBoardRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BedBoardRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BedBoardRepository>(value),
    );
  }
}

String _$bedBoardRepositoryHash() =>
    r'b17864291eb31506e58bff316faac7caf87171a4';

/// Open rooms and their active beds, watched (drift `watch()`).

@ProviderFor(boardRooms)
final boardRoomsProvider = BoardRoomsProvider._();

/// Open rooms and their active beds, watched (drift `watch()`).

final class BoardRoomsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BoardRoom>>,
          List<BoardRoom>,
          Stream<List<BoardRoom>>
        >
    with $FutureModifier<List<BoardRoom>>, $StreamProvider<List<BoardRoom>> {
  /// Open rooms and their active beds, watched (drift `watch()`).
  BoardRoomsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardRoomsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardRoomsHash();

  @$internal
  @override
  $StreamProviderElement<List<BoardRoom>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<BoardRoom>> create(Ref ref) {
    return boardRooms(ref);
  }
}

String _$boardRoomsHash() => r'3f1fb87cdacfe85debbc53673e5b1f21e6288bab';

/// The grace setting, watched.

@ProviderFor(boardGraceMinutes)
final boardGraceMinutesProvider = BoardGraceMinutesProvider._();

/// The grace setting, watched.

final class BoardGraceMinutesProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// The grace setting, watched.
  BoardGraceMinutesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardGraceMinutesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardGraceMinutesHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return boardGraceMinutes(ref);
  }
}

String _$boardGraceMinutesHash() => r'a2f17128170da526d9deef66abea0a0c3067766e';

/// How often the board re-reads the clock, so a bed turns Overstay on its
/// own (FD-7). Null in tests: no timer, the clock is set by hand.

@ProviderFor(boardTickInterval)
final boardTickIntervalProvider = BoardTickIntervalProvider._();

/// How often the board re-reads the clock, so a bed turns Overstay on its
/// own (FD-7). Null in tests: no timer, the clock is set by hand.

final class BoardTickIntervalProvider
    extends $FunctionalProvider<Duration?, Duration?, Duration?>
    with $Provider<Duration?> {
  /// How often the board re-reads the clock, so a bed turns Overstay on its
  /// own (FD-7). Null in tests: no timer, the clock is set by hand.
  BoardTickIntervalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardTickIntervalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardTickIntervalHash();

  @$internal
  @override
  $ProviderElement<Duration?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration? create(Ref ref) {
    return boardTickInterval(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration?>(value),
    );
  }
}

String _$boardTickIntervalHash() => r'4d690c3c84a53e1f2558c1e9065eff3825c6c793';

/// "Now" for the board: once at once, then every [boardTickInterval]. Ends
/// with the board (auto-dispose), which stops the timer.

@ProviderFor(boardNow)
final boardNowProvider = BoardNowProvider._();

/// "Now" for the board: once at once, then every [boardTickInterval]. Ends
/// with the board (auto-dispose), which stops the timer.

final class BoardNowProvider
    extends
        $FunctionalProvider<AsyncValue<DateTime>, DateTime, Stream<DateTime>>
    with $FutureModifier<DateTime>, $StreamProvider<DateTime> {
  /// "Now" for the board: once at once, then every [boardTickInterval]. Ends
  /// with the board (auto-dispose), which stops the timer.
  BoardNowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardNowProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardNowHash();

  @$internal
  @override
  $StreamProviderElement<DateTime> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<DateTime> create(Ref ref) {
    return boardNow(ref);
  }
}

String _$boardNowHash() => r'56d579ca8e22688d2ce200eeb410c74d866c823e';
