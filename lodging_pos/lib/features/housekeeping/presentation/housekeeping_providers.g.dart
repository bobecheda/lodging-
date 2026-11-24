// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'housekeeping_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(housekeepingRepository)
final housekeepingRepositoryProvider = HousekeepingRepositoryProvider._();

final class HousekeepingRepositoryProvider
    extends
        $FunctionalProvider<
          HousekeepingRepository,
          HousekeepingRepository,
          HousekeepingRepository
        >
    with $Provider<HousekeepingRepository> {
  HousekeepingRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'housekeepingRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$housekeepingRepositoryHash();

  @$internal
  @override
  $ProviderElement<HousekeepingRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  HousekeepingRepository create(Ref ref) {
    return housekeepingRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HousekeepingRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HousekeepingRepository>(value),
    );
  }
}

String _$housekeepingRepositoryHash() =>
    r'551fb73e8bb41c647a70633b48748af7f6314117';

/// One bed for the cleaning panel, watched.

@ProviderFor(bedCleaning)
final bedCleaningProvider = BedCleaningFamily._();

/// One bed for the cleaning panel, watched.

final class BedCleaningProvider
    extends
        $FunctionalProvider<
          AsyncValue<BedCleaning>,
          BedCleaning,
          Stream<BedCleaning>
        >
    with $FutureModifier<BedCleaning>, $StreamProvider<BedCleaning> {
  /// One bed for the cleaning panel, watched.
  BedCleaningProvider._({
    required BedCleaningFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'bedCleaningProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$bedCleaningHash();

  @override
  String toString() {
    return r'bedCleaningProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<BedCleaning> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BedCleaning> create(Ref ref) {
    final argument = this.argument as String;
    return bedCleaning(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is BedCleaningProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$bedCleaningHash() => r'2a0ac6263a7434ad196304cdb8787ce2c9aca6a2';

/// One bed for the cleaning panel, watched.

final class BedCleaningFamily extends $Family
    with $FunctionalFamilyOverride<Stream<BedCleaning>, String> {
  BedCleaningFamily._()
    : super(
        retry: null,
        name: r'bedCleaningProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One bed for the cleaning panel, watched.

  BedCleaningProvider call(String bedId) =>
      BedCleaningProvider._(argument: bedId, from: this);

  @override
  String toString() => r'bedCleaningProvider';
}

/// When a bed was last cleaned and by whom, for the check-in header (v2 PR
/// 5); null if never.

@ProviderFor(lastCleaned)
final lastCleanedProvider = LastCleanedFamily._();

/// When a bed was last cleaned and by whom, for the check-in header (v2 PR
/// 5); null if never.

final class LastCleanedProvider
    extends
        $FunctionalProvider<
          AsyncValue<({DateTime at, String by})?>,
          ({DateTime at, String by})?,
          FutureOr<({DateTime at, String by})?>
        >
    with
        $FutureModifier<({DateTime at, String by})?>,
        $FutureProvider<({DateTime at, String by})?> {
  /// When a bed was last cleaned and by whom, for the check-in header (v2 PR
  /// 5); null if never.
  LastCleanedProvider._({
    required LastCleanedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lastCleanedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lastCleanedHash();

  @override
  String toString() {
    return r'lastCleanedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<({DateTime at, String by})?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<({DateTime at, String by})?> create(Ref ref) {
    final argument = this.argument as String;
    return lastCleaned(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LastCleanedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lastCleanedHash() => r'a823301e742cd78a5a712ae37e75dde96d472739';

/// When a bed was last cleaned and by whom, for the check-in header (v2 PR
/// 5); null if never.

final class LastCleanedFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<({DateTime at, String by})?>,
          String
        > {
  LastCleanedFamily._()
    : super(
        retry: null,
        name: r'lastCleanedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// When a bed was last cleaned and by whom, for the check-in header (v2 PR
  /// 5); null if never.

  LastCleanedProvider call(String bedId) =>
      LastCleanedProvider._(argument: bedId, from: this);

  @override
  String toString() => r'lastCleanedProvider';
}

/// Active housekeepers, for the dropdown.

@ProviderFor(activeHousekeepers)
final activeHousekeepersProvider = ActiveHousekeepersProvider._();

/// Active housekeepers, for the dropdown.

final class ActiveHousekeepersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<HousekeeperOption>>,
          List<HousekeeperOption>,
          Stream<List<HousekeeperOption>>
        >
    with
        $FutureModifier<List<HousekeeperOption>>,
        $StreamProvider<List<HousekeeperOption>> {
  /// Active housekeepers, for the dropdown.
  ActiveHousekeepersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeHousekeepersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeHousekeepersHash();

  @$internal
  @override
  $StreamProviderElement<List<HousekeeperOption>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<HousekeeperOption>> create(Ref ref) {
    return activeHousekeepers(ref);
  }
}

String _$activeHousekeepersHash() =>
    r'31c6294261aa9d7592b134ef4105cd33fc21dfef';
