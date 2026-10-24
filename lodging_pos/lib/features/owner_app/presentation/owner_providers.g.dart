// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'owner_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Supabase project, from `secrets.json` at build time; null in a build
/// without it (the sign-in screen says so).

@ProviderFor(ownerCloud)
final ownerCloudProvider = OwnerCloudProvider._();

/// The Supabase project, from `secrets.json` at build time; null in a build
/// without it (the sign-in screen says so).

final class OwnerCloudProvider
    extends $FunctionalProvider<OwnerCloud?, OwnerCloud?, OwnerCloud?>
    with $Provider<OwnerCloud?> {
  /// The Supabase project, from `secrets.json` at build time; null in a build
  /// without it (the sign-in screen says so).
  OwnerCloudProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownerCloudProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownerCloudHash();

  @$internal
  @override
  $ProviderElement<OwnerCloud?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OwnerCloud? create(Ref ref) {
    return ownerCloud(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OwnerCloud? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OwnerCloud?>(value),
    );
  }
}

String _$ownerCloudHash() => r'15c8511eeecc5a8b72e284fff545d3806a5c9a35';

/// How often Today reloads while open; null turns the timer off (tests).

@ProviderFor(ownerRefreshInterval)
final ownerRefreshIntervalProvider = OwnerRefreshIntervalProvider._();

/// How often Today reloads while open; null turns the timer off (tests).

final class OwnerRefreshIntervalProvider
    extends $FunctionalProvider<Duration?, Duration?, Duration?>
    with $Provider<Duration?> {
  /// How often Today reloads while open; null turns the timer off (tests).
  OwnerRefreshIntervalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownerRefreshIntervalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownerRefreshIntervalHash();

  @$internal
  @override
  $ProviderElement<Duration?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration? create(Ref ref) {
    return ownerRefreshInterval(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration?>(value),
    );
  }
}

String _$ownerRefreshIntervalHash() =>
    r'2f196cdec7db508c6c30b6350ffe7b73f8b83946';

/// The owner's sign-in on this phone: kept until Sign out (or until the
/// cloud stops renewing it, e.g. after a password change elsewhere).

@ProviderFor(OwnerSession)
final ownerSessionProvider = OwnerSessionProvider._();

/// The owner's sign-in on this phone: kept until Sign out (or until the
/// cloud stops renewing it, e.g. after a password change elsewhere).
final class OwnerSessionProvider
    extends $AsyncNotifierProvider<OwnerSession, OwnerSignIn?> {
  /// The owner's sign-in on this phone: kept until Sign out (or until the
  /// cloud stops renewing it, e.g. after a password change elsewhere).
  OwnerSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownerSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownerSessionHash();

  @$internal
  @override
  OwnerSession create() => OwnerSession();
}

String _$ownerSessionHash() => r'19bc99b2d269ac7535f1a1b6ea00398b3e1abad1';

/// The owner's sign-in on this phone: kept until Sign out (or until the
/// cloud stops renewing it, e.g. after a password change elsewhere).

abstract class _$OwnerSession extends $AsyncNotifier<OwnerSignIn?> {
  FutureOr<OwnerSignIn?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<OwnerSignIn?>, OwnerSignIn?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OwnerSignIn?>, OwnerSignIn?>,
              AsyncValue<OwnerSignIn?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Today: loaded on open, again on return to the app (the shell), on a
/// pull and every [ownerRefreshInterval]. Null once signed out: the
/// figures are dropped.

@ProviderFor(OwnerTodayData)
final ownerTodayDataProvider = OwnerTodayDataProvider._();

/// Today: loaded on open, again on return to the app (the shell), on a
/// pull and every [ownerRefreshInterval]. Null once signed out: the
/// figures are dropped.
final class OwnerTodayDataProvider
    extends $AsyncNotifierProvider<OwnerTodayData, OwnerSnapshot?> {
  /// Today: loaded on open, again on return to the app (the shell), on a
  /// pull and every [ownerRefreshInterval]. Null once signed out: the
  /// figures are dropped.
  OwnerTodayDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownerTodayDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownerTodayDataHash();

  @$internal
  @override
  OwnerTodayData create() => OwnerTodayData();
}

String _$ownerTodayDataHash() => r'349f1befe0fbc69c2afd2b11e331f550a9745415';

/// Today: loaded on open, again on return to the app (the shell), on a
/// pull and every [ownerRefreshInterval]. Null once signed out: the
/// figures are dropped.

abstract class _$OwnerTodayData extends $AsyncNotifier<OwnerSnapshot?> {
  FutureOr<OwnerSnapshot?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<OwnerSnapshot?>, OwnerSnapshot?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OwnerSnapshot?>, OwnerSnapshot?>,
              AsyncValue<OwnerSnapshot?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ownerRefundsRepository)
final ownerRefundsRepositoryProvider = OwnerRefundsRepositoryProvider._();

final class OwnerRefundsRepositoryProvider
    extends
        $FunctionalProvider<
          OwnerRefundsRepository,
          OwnerRefundsRepository,
          OwnerRefundsRepository
        >
    with $Provider<OwnerRefundsRepository> {
  OwnerRefundsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownerRefundsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownerRefundsRepositoryHash();

  @$internal
  @override
  $ProviderElement<OwnerRefundsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OwnerRefundsRepository create(Ref ref) {
    return ownerRefundsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OwnerRefundsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OwnerRefundsRepository>(value),
    );
  }
}

String _$ownerRefundsRepositoryHash() =>
    r'3f00b3a63e6248ecda9ae67a122231ae1f050d4e';

/// One refund's detail, read when its screen opens.

@ProviderFor(ownerRefund)
final ownerRefundProvider = OwnerRefundFamily._();

/// One refund's detail, read when its screen opens.

final class OwnerRefundProvider
    extends
        $FunctionalProvider<
          AsyncValue<OwnerRefund>,
          OwnerRefund,
          FutureOr<OwnerRefund>
        >
    with $FutureModifier<OwnerRefund>, $FutureProvider<OwnerRefund> {
  /// One refund's detail, read when its screen opens.
  OwnerRefundProvider._({
    required OwnerRefundFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'ownerRefundProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ownerRefundHash();

  @override
  String toString() {
    return r'ownerRefundProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<OwnerRefund> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<OwnerRefund> create(Ref ref) {
    final argument = this.argument as String;
    return ownerRefund(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OwnerRefundProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ownerRefundHash() => r'c2a04da6ccb1407f20778de6cc8821d69983ebcb';

/// One refund's detail, read when its screen opens.

final class OwnerRefundFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<OwnerRefund>, String> {
  OwnerRefundFamily._()
    : super(
        retry: null,
        name: r'ownerRefundProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One refund's detail, read when its screen opens.

  OwnerRefundProvider call(String refundId) =>
      OwnerRefundProvider._(argument: refundId, from: this);

  @override
  String toString() => r'ownerRefundProvider';
}
