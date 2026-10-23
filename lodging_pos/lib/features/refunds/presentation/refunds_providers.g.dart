// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'refunds_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(refundsRepository)
final refundsRepositoryProvider = RefundsRepositoryProvider._();

final class RefundsRepositoryProvider
    extends
        $FunctionalProvider<
          RefundsRepository,
          RefundsRepository,
          RefundsRepository
        >
    with $Provider<RefundsRepository> {
  RefundsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'refundsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$refundsRepositoryHash();

  @$internal
  @override
  $ProviderElement<RefundsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RefundsRepository create(Ref ref) {
    return refundsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RefundsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RefundsRepository>(value),
    );
  }
}

String _$refundsRepositoryHash() => r'c2aa84993eaa70e7fe750c23045ee9b6d4eae3d7';

/// The desk's Refunds lists, read again whenever a refund, decision or
/// payout changes.

@ProviderFor(deskRefunds)
final deskRefundsProvider = DeskRefundsProvider._();

/// The desk's Refunds lists, read again whenever a refund, decision or
/// payout changes.

final class DeskRefundsProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeskRefunds>,
          DeskRefunds,
          Stream<DeskRefunds>
        >
    with $FutureModifier<DeskRefunds>, $StreamProvider<DeskRefunds> {
  /// The desk's Refunds lists, read again whenever a refund, decision or
  /// payout changes.
  DeskRefundsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deskRefundsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deskRefundsHash();

  @$internal
  @override
  $StreamProviderElement<DeskRefunds> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<DeskRefunds> create(Ref ref) {
    return deskRefunds(ref);
  }
}

String _$deskRefundsHash() => r'98f7ce5c06996e3029963868d1b051b53afcef46';

/// Approved refunds waiting to be paid: the Refunds sidebar badge.

@ProviderFor(refundsToPay)
final refundsToPayProvider = RefundsToPayProvider._();

/// Approved refunds waiting to be paid: the Refunds sidebar badge.

final class RefundsToPayProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// Approved refunds waiting to be paid: the Refunds sidebar badge.
  RefundsToPayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'refundsToPayProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$refundsToPayHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return refundsToPay(ref);
  }
}

String _$refundsToPayHash() => r'6b44665f8b1b683384fe9241f0745b65a9f65143';

/// One refund for the owner's detail, read again when it changes.

@ProviderFor(refundDetail)
final refundDetailProvider = RefundDetailFamily._();

/// One refund for the owner's detail, read again when it changes.

final class RefundDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<RefundDetail>,
          RefundDetail,
          Stream<RefundDetail>
        >
    with $FutureModifier<RefundDetail>, $StreamProvider<RefundDetail> {
  /// One refund for the owner's detail, read again when it changes.
  RefundDetailProvider._({
    required RefundDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'refundDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$refundDetailHash();

  @override
  String toString() {
    return r'refundDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<RefundDetail> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RefundDetail> create(Ref ref) {
    final argument = this.argument as String;
    return refundDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RefundDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$refundDetailHash() => r'95325554a69605b5b28defefe85deba99f456b0d';

/// One refund for the owner's detail, read again when it changes.

final class RefundDetailFamily extends $Family
    with $FunctionalFamilyOverride<Stream<RefundDetail>, String> {
  RefundDetailFamily._()
    : super(
        retry: null,
        name: r'refundDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One refund for the owner's detail, read again when it changes.

  RefundDetailProvider call(String refundId) =>
      RefundDetailProvider._(argument: refundId, from: this);

  @override
  String toString() => r'refundDetailProvider';
}

/// One refund for the pay panel, read again when it changes.

@ProviderFor(refundView)
final refundViewProvider = RefundViewFamily._();

/// One refund for the pay panel, read again when it changes.

final class RefundViewProvider
    extends
        $FunctionalProvider<
          AsyncValue<RefundView>,
          RefundView,
          Stream<RefundView>
        >
    with $FutureModifier<RefundView>, $StreamProvider<RefundView> {
  /// One refund for the pay panel, read again when it changes.
  RefundViewProvider._({
    required RefundViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'refundViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$refundViewHash();

  @override
  String toString() {
    return r'refundViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<RefundView> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<RefundView> create(Ref ref) {
    final argument = this.argument as String;
    return refundView(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RefundViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$refundViewHash() => r'3f28c13c6f90abbb0f2fab480025b5bd5404ffa6';

/// One refund for the pay panel, read again when it changes.

final class RefundViewFamily extends $Family
    with $FunctionalFamilyOverride<Stream<RefundView>, String> {
  RefundViewFamily._()
    : super(
        retry: null,
        name: r'refundViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One refund for the pay panel, read again when it changes.

  RefundViewProvider call(String refundId) =>
      RefundViewProvider._(argument: refundId, from: this);

  @override
  String toString() => r'refundViewProvider';
}
