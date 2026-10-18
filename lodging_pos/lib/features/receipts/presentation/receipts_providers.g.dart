// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipts_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(receiptsRepository)
final receiptsRepositoryProvider = ReceiptsRepositoryProvider._();

final class ReceiptsRepositoryProvider
    extends
        $FunctionalProvider<
          ReceiptsRepository,
          ReceiptsRepository,
          ReceiptsRepository
        >
    with $Provider<ReceiptsRepository> {
  ReceiptsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiptsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiptsRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReceiptsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReceiptsRepository create(Ref ref) {
    return receiptsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiptsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiptsRepository>(value),
    );
  }
}

String _$receiptsRepositoryHash() =>
    r'8f3ea0110616264b17ccbff4d429f23912de7b3a';

/// One receipt, watched: it turns into a COPY as soon as it's printed.

@ProviderFor(receipt)
final receiptProvider = ReceiptFamily._();

/// One receipt, watched: it turns into a COPY as soon as it's printed.

final class ReceiptProvider
    extends $FunctionalProvider<AsyncValue<Receipt>, Receipt, Stream<Receipt>>
    with $FutureModifier<Receipt>, $StreamProvider<Receipt> {
  /// One receipt, watched: it turns into a COPY as soon as it's printed.
  ReceiptProvider._({
    required ReceiptFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'receiptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$receiptHash();

  @override
  String toString() {
    return r'receiptProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Receipt> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Receipt> create(Ref ref) {
    final argument = this.argument as String;
    return receipt(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReceiptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$receiptHash() => r'9cecc7b74aa2a39a1631e3cef425cb15f4c0c6e8';

/// One receipt, watched: it turns into a COPY as soon as it's printed.

final class ReceiptFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Receipt>, String> {
  ReceiptFamily._()
    : super(
        retry: null,
        name: r'receiptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One receipt, watched: it turns into a COPY as soon as it's printed.

  ReceiptProvider call(String paymentId) =>
      ReceiptProvider._(argument: paymentId, from: this);

  @override
  String toString() => r'receiptProvider';
}

/// The Receipts list for what's typed in its search box.

@ProviderFor(receiptList)
final receiptListProvider = ReceiptListFamily._();

/// The Receipts list for what's typed in its search box.

final class ReceiptListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ReceiptSummary>>,
          List<ReceiptSummary>,
          Stream<List<ReceiptSummary>>
        >
    with
        $FutureModifier<List<ReceiptSummary>>,
        $StreamProvider<List<ReceiptSummary>> {
  /// The Receipts list for what's typed in its search box.
  ReceiptListProvider._({
    required ReceiptListFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'receiptListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$receiptListHash();

  @override
  String toString() {
    return r'receiptListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<ReceiptSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ReceiptSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return receiptList(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReceiptListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$receiptListHash() => r'49072da8a3882cff5b22f0e0e6ed7b3429602c30';

/// The Receipts list for what's typed in its search box.

final class ReceiptListFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<ReceiptSummary>>, String> {
  ReceiptListFamily._()
    : super(
        retry: null,
        name: r'receiptListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The Receipts list for what's typed in its search box.

  ReceiptListProvider call(String text) =>
      ReceiptListProvider._(argument: text, from: this);

  @override
  String toString() => r'receiptListProvider';
}

/// The bundled fonts, embedded in every receipt PDF.

@ProviderFor(receiptFonts)
final receiptFontsProvider = ReceiptFontsProvider._();

/// The bundled fonts, embedded in every receipt PDF.

final class ReceiptFontsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReceiptFonts>,
          ReceiptFonts,
          FutureOr<ReceiptFonts>
        >
    with $FutureModifier<ReceiptFonts>, $FutureProvider<ReceiptFonts> {
  /// The bundled fonts, embedded in every receipt PDF.
  ReceiptFontsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiptFontsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiptFontsHash();

  @$internal
  @override
  $FutureProviderElement<ReceiptFonts> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ReceiptFonts> create(Ref ref) {
    return receiptFonts(ref);
  }
}

String _$receiptFontsHash() => r'721b410fa36ede041342827a21746f8b069c24ed';

@ProviderFor(receiptOutput)
final receiptOutputProvider = ReceiptOutputProvider._();

final class ReceiptOutputProvider
    extends $FunctionalProvider<ReceiptOutput, ReceiptOutput, ReceiptOutput>
    with $Provider<ReceiptOutput> {
  ReceiptOutputProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiptOutputProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiptOutputHash();

  @$internal
  @override
  $ProviderElement<ReceiptOutput> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ReceiptOutput create(Ref ref) {
    return receiptOutput(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiptOutput value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiptOutput>(value),
    );
  }
}

String _$receiptOutputHash() => r'70c2a3eda9987282debfbe58558c76741814539a';
