// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'check_in_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(checkInRepository)
final checkInRepositoryProvider = CheckInRepositoryProvider._();

final class CheckInRepositoryProvider
    extends
        $FunctionalProvider<
          CheckInRepository,
          CheckInRepository,
          CheckInRepository
        >
    with $Provider<CheckInRepository> {
  CheckInRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkInRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkInRepositoryHash();

  @$internal
  @override
  $ProviderElement<CheckInRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CheckInRepository create(Ref ref) {
    return checkInRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CheckInRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CheckInRepository>(value),
    );
  }
}

String _$checkInRepositoryHash() => r'802924ebc867ae7855f3d396c29c476b1b56d779';

/// Open rooms with every bed, watched: the bed choices and Bed B's reason.

@ProviderFor(checkInRooms)
final checkInRoomsProvider = CheckInRoomsProvider._();

/// Open rooms with every bed, watched: the bed choices and Bed B's reason.

final class CheckInRoomsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RoomSummary>>,
          List<RoomSummary>,
          Stream<List<RoomSummary>>
        >
    with
        $FutureModifier<List<RoomSummary>>,
        $StreamProvider<List<RoomSummary>> {
  /// Open rooms with every bed, watched: the bed choices and Bed B's reason.
  CheckInRoomsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkInRoomsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkInRoomsHash();

  @$internal
  @override
  $StreamProviderElement<List<RoomSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<RoomSummary>> create(Ref ref) {
    return checkInRooms(ref);
  }
}

String _$checkInRoomsHash() => r'd9eb0617bf21c583ce01bd85d38d5bf8be972ece';

/// The checkout time setting, watched, for the dates shown.

@ProviderFor(checkInCheckoutTime)
final checkInCheckoutTimeProvider = CheckInCheckoutTimeProvider._();

/// The checkout time setting, watched, for the dates shown.

final class CheckInCheckoutTimeProvider
    extends
        $FunctionalProvider<AsyncValue<ClockTime>, ClockTime, Stream<ClockTime>>
    with $FutureModifier<ClockTime>, $StreamProvider<ClockTime> {
  /// The checkout time setting, watched, for the dates shown.
  CheckInCheckoutTimeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkInCheckoutTimeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkInCheckoutTimeHash();

  @$internal
  @override
  $StreamProviderElement<ClockTime> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<ClockTime> create(Ref ref) {
    return checkInCheckoutTime(ref);
  }
}

String _$checkInCheckoutTimeHash() =>
    r'91d25f387500f800f119789f2e2220825337b5b3';

/// A returning guest's earlier check-ins, for their card.

@ProviderFor(guestHistory)
final guestHistoryProvider = GuestHistoryFamily._();

/// A returning guest's earlier check-ins, for their card.

final class GuestHistoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<GuestHistory>,
          GuestHistory,
          FutureOr<GuestHistory>
        >
    with $FutureModifier<GuestHistory>, $FutureProvider<GuestHistory> {
  /// A returning guest's earlier check-ins, for their card.
  GuestHistoryProvider._({
    required GuestHistoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'guestHistoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$guestHistoryHash();

  @override
  String toString() {
    return r'guestHistoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<GuestHistory> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<GuestHistory> create(Ref ref) {
    final argument = this.argument as String;
    return guestHistory(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GuestHistoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$guestHistoryHash() => r'df8aa7144b3d685a8823096e7ee6c0e7252f5bd7';

/// A returning guest's earlier check-ins, for their card.

final class GuestHistoryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<GuestHistory>, String> {
  GuestHistoryFamily._()
    : super(
        retry: null,
        name: r'guestHistoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A returning guest's earlier check-ins, for their card.

  GuestHistoryProvider call(String guestId) =>
      GuestHistoryProvider._(argument: guestId, from: this);

  @override
  String toString() => r'guestHistoryProvider';
}

@ProviderFor(checkOutRepository)
final checkOutRepositoryProvider = CheckOutRepositoryProvider._();

final class CheckOutRepositoryProvider
    extends
        $FunctionalProvider<
          CheckOutRepository,
          CheckOutRepository,
          CheckOutRepository
        >
    with $Provider<CheckOutRepository> {
  CheckOutRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkOutRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkOutRepositoryHash();

  @$internal
  @override
  $ProviderElement<CheckOutRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CheckOutRepository create(Ref ref) {
    return checkOutRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CheckOutRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CheckOutRepository>(value),
    );
  }
}

String _$checkOutRepositoryHash() =>
    r'7d53c372ff442db5a06a6770c25e58d72acaa423';

/// One stay as the bed panel shows it, watched.

@ProviderFor(stayDetail)
final stayDetailProvider = StayDetailFamily._();

/// One stay as the bed panel shows it, watched.

final class StayDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<StayDetail>,
          StayDetail,
          Stream<StayDetail>
        >
    with $FutureModifier<StayDetail>, $StreamProvider<StayDetail> {
  /// One stay as the bed panel shows it, watched.
  StayDetailProvider._({
    required StayDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'stayDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$stayDetailHash();

  @override
  String toString() {
    return r'stayDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<StayDetail> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<StayDetail> create(Ref ref) {
    final argument = this.argument as String;
    return stayDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is StayDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$stayDetailHash() => r'3151f57c509f267643d59effc597c7e3ec4c0e94';

/// One stay as the bed panel shows it, watched.

final class StayDetailFamily extends $Family
    with $FunctionalFamilyOverride<Stream<StayDetail>, String> {
  StayDetailFamily._()
    : super(
        retry: null,
        name: r'stayDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One stay as the bed panel shows it, watched.

  StayDetailProvider call(String stayId) =>
      StayDetailProvider._(argument: stayId, from: this);

  @override
  String toString() => r'stayDetailProvider';
}

@ProviderFor(extendRepository)
final extendRepositoryProvider = ExtendRepositoryProvider._();

final class ExtendRepositoryProvider
    extends
        $FunctionalProvider<
          ExtendRepository,
          ExtendRepository,
          ExtendRepository
        >
    with $Provider<ExtendRepository> {
  ExtendRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'extendRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$extendRepositoryHash();

  @$internal
  @override
  $ProviderElement<ExtendRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ExtendRepository create(Ref ref) {
    return extendRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExtendRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExtendRepository>(value),
    );
  }
}

String _$extendRepositoryHash() => r'f71308623cab4f5369f38a109635a0204ea8d280';
