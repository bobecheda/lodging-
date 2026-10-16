// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(staffRepository)
final staffRepositoryProvider = StaffRepositoryProvider._();

final class StaffRepositoryProvider
    extends
        $FunctionalProvider<StaffRepository, StaffRepository, StaffRepository>
    with $Provider<StaffRepository> {
  StaffRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'staffRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$staffRepositoryHash();

  @$internal
  @override
  $ProviderElement<StaffRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StaffRepository create(Ref ref) {
    return staffRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StaffRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StaffRepository>(value),
    );
  }
}

String _$staffRepositoryHash() => r'9f91db0a4a180df63904a8012b05b7f656b6f1e3';

/// Everyone who signs in. Invalidate after a write.

@ProviderFor(staffUsers)
final staffUsersProvider = StaffUsersProvider._();

/// Everyone who signs in. Invalidate after a write.

final class StaffUsersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<UserSummary>>,
          List<UserSummary>,
          FutureOr<List<UserSummary>>
        >
    with
        $FutureModifier<List<UserSummary>>,
        $FutureProvider<List<UserSummary>> {
  /// Everyone who signs in. Invalidate after a write.
  StaffUsersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'staffUsersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$staffUsersHash();

  @$internal
  @override
  $FutureProviderElement<List<UserSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<UserSummary>> create(Ref ref) {
    return staffUsers(ref);
  }
}

String _$staffUsersHash() => r'53e738a76571f53e976f78a48225d3db9a4eda35';

/// Housekeepers, active first. Invalidate after a write.

@ProviderFor(housekeepersList)
final housekeepersListProvider = HousekeepersListProvider._();

/// Housekeepers, active first. Invalidate after a write.

final class HousekeepersListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Housekeeper>>,
          List<Housekeeper>,
          FutureOr<List<Housekeeper>>
        >
    with
        $FutureModifier<List<Housekeeper>>,
        $FutureProvider<List<Housekeeper>> {
  /// Housekeepers, active first. Invalidate after a write.
  HousekeepersListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'housekeepersListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$housekeepersListHash();

  @$internal
  @override
  $FutureProviderElement<List<Housekeeper>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Housekeeper>> create(Ref ref) {
    return housekeepersList(ref);
  }
}

String _$housekeepersListHash() => r'2fc7393e33bc74581ab75c352f1c8296a17d49f2';
