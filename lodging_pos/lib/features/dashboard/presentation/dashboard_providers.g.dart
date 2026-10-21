// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dashboardRepository)
final dashboardRepositoryProvider = DashboardRepositoryProvider._();

final class DashboardRepositoryProvider
    extends
        $FunctionalProvider<
          DashboardRepository,
          DashboardRepository,
          DashboardRepository
        >
    with $Provider<DashboardRepository> {
  DashboardRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dashboardRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dashboardRepositoryHash();

  @$internal
  @override
  $ProviderElement<DashboardRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DashboardRepository create(Ref ref) {
    return dashboardRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DashboardRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DashboardRepository>(value),
    );
  }
}

String _$dashboardRepositoryHash() =>
    r'e06e89b2e8d4669bf60cec2b990bf63940ff723f';

/// Read again whenever a payment, refund, void, stay or charge changes.

@ProviderFor(todayData)
final todayDataProvider = TodayDataProvider._();

/// Read again whenever a payment, refund, void, stay or charge changes.

final class TodayDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<TodayData>,
          TodayData,
          FutureOr<TodayData>
        >
    with $FutureModifier<TodayData>, $FutureProvider<TodayData> {
  /// Read again whenever a payment, refund, void, stay or charge changes.
  TodayDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todayDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todayDataHash();

  @$internal
  @override
  $FutureProviderElement<TodayData> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<TodayData> create(Ref ref) {
    return todayData(ref);
  }
}

String _$todayDataHash() => r'a1e63ecbf553a11d74dd905f391646a370dce7e5';
