// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rooms_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(roomsRepository)
final roomsRepositoryProvider = RoomsRepositoryProvider._();

final class RoomsRepositoryProvider
    extends
        $FunctionalProvider<RoomsRepository, RoomsRepository, RoomsRepository>
    with $Provider<RoomsRepository> {
  RoomsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomsRepositoryHash();

  @$internal
  @override
  $ProviderElement<RoomsRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoomsRepository create(Ref ref) {
    return roomsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomsRepository>(value),
    );
  }
}

String _$roomsRepositoryHash() => r'1b1f0f49dcfd883f9a9e928572701e965e40b1aa';

/// All rooms with their beds, naturally sorted. Call `ref.invalidate` after a
/// write to reload.

@ProviderFor(roomsList)
final roomsListProvider = RoomsListProvider._();

/// All rooms with their beds, naturally sorted. Call `ref.invalidate` after a
/// write to reload.

final class RoomsListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RoomSummary>>,
          List<RoomSummary>,
          FutureOr<List<RoomSummary>>
        >
    with
        $FutureModifier<List<RoomSummary>>,
        $FutureProvider<List<RoomSummary>> {
  /// All rooms with their beds, naturally sorted. Call `ref.invalidate` after a
  /// write to reload.
  RoomsListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomsListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomsListHash();

  @$internal
  @override
  $FutureProviderElement<List<RoomSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RoomSummary>> create(Ref ref) {
    return roomsList(ref);
  }
}

String _$roomsListHash() => r'194c4c821c148a72145a9c75c2895f5fc4ac4f47';

/// Bed categories for the selects (active and inactive, in sort order).

@ProviderFor(bedCategories)
final bedCategoriesProvider = BedCategoriesProvider._();

/// Bed categories for the selects (active and inactive, in sort order).

final class BedCategoriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BedCategory>>,
          List<BedCategory>,
          FutureOr<List<BedCategory>>
        >
    with
        $FutureModifier<List<BedCategory>>,
        $FutureProvider<List<BedCategory>> {
  /// Bed categories for the selects (active and inactive, in sort order).
  BedCategoriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bedCategoriesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bedCategoriesHash();

  @$internal
  @override
  $FutureProviderElement<List<BedCategory>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<BedCategory>> create(Ref ref) {
    return bedCategories(ref);
  }
}

String _$bedCategoriesHash() => r'ea7b9eb4a48a889700cb9c3c29cc2c36f3c65360';
