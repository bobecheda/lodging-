// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_requests_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(priceRequestsRepository)
final priceRequestsRepositoryProvider = PriceRequestsRepositoryProvider._();

final class PriceRequestsRepositoryProvider
    extends
        $FunctionalProvider<
          PriceRequestsRepository,
          PriceRequestsRepository,
          PriceRequestsRepository
        >
    with $Provider<PriceRequestsRepository> {
  PriceRequestsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'priceRequestsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$priceRequestsRepositoryHash();

  @$internal
  @override
  $ProviderElement<PriceRequestsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PriceRequestsRepository create(Ref ref) {
    return priceRequestsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PriceRequestsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PriceRequestsRepository>(value),
    );
  }
}

String _$priceRequestsRepositoryHash() =>
    r'089fed4ad07c9eaa072e189233fb1a6ff783f9de';

/// Requests waiting for the owner, oldest first: the owner's Prices cards
/// and sidebar badge. Read again whenever a request, decision or price
/// changes.

@ProviderFor(waitingPriceRequests)
final waitingPriceRequestsProvider = WaitingPriceRequestsProvider._();

/// Requests waiting for the owner, oldest first: the owner's Prices cards
/// and sidebar badge. Read again whenever a request, decision or price
/// changes.

final class WaitingPriceRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PriceRequestView>>,
          List<PriceRequestView>,
          Stream<List<PriceRequestView>>
        >
    with
        $FutureModifier<List<PriceRequestView>>,
        $StreamProvider<List<PriceRequestView>> {
  /// Requests waiting for the owner, oldest first: the owner's Prices cards
  /// and sidebar badge. Read again whenever a request, decision or price
  /// changes.
  WaitingPriceRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'waitingPriceRequestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$waitingPriceRequestsHash();

  @$internal
  @override
  $StreamProviderElement<List<PriceRequestView>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<PriceRequestView>> create(Ref ref) {
    return waitingPriceRequests(ref);
  }
}

String _$waitingPriceRequestsHash() =>
    r'5d2ca3ff6096a1be207ee34d9615d425dc8ba346';

/// The supervisor's Price requests card, read again on every change.

@ProviderFor(supervisorPriceRequests)
final supervisorPriceRequestsProvider = SupervisorPriceRequestsProvider._();

/// The supervisor's Price requests card, read again on every change.

final class SupervisorPriceRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<SupervisorPriceRequests>,
          SupervisorPriceRequests,
          Stream<SupervisorPriceRequests>
        >
    with
        $FutureModifier<SupervisorPriceRequests>,
        $StreamProvider<SupervisorPriceRequests> {
  /// The supervisor's Price requests card, read again on every change.
  SupervisorPriceRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'supervisorPriceRequestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$supervisorPriceRequestsHash();

  @$internal
  @override
  $StreamProviderElement<SupervisorPriceRequests> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<SupervisorPriceRequests> create(Ref ref) {
    return supervisorPriceRequests(ref);
  }
}

String _$supervisorPriceRequestsHash() =>
    r'a21eee5ef126bdc20b2c36087140a01ec31abff0';
