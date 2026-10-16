// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prices_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(pricesRepository)
final pricesRepositoryProvider = PricesRepositoryProvider._();

final class PricesRepositoryProvider
    extends
        $FunctionalProvider<
          PricesRepository,
          PricesRepository,
          PricesRepository
        >
    with $Provider<PricesRepository> {
  PricesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pricesRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pricesRepositoryHash();

  @$internal
  @override
  $ProviderElement<PricesRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PricesRepository create(Ref ref) {
    return pricesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PricesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PricesRepository>(value),
    );
  }
}

String _$pricesRepositoryHash() => r'98062ec013089b5b6d868d5c2e97290981454c92';

/// Categories in sort order with their active beds. Invalidate after a write.

@ProviderFor(categoryUsage)
final categoryUsageProvider = CategoryUsageProvider._();

/// Categories in sort order with their active beds. Invalidate after a write.

final class CategoryUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CategoryUsage>>,
          List<CategoryUsage>,
          FutureOr<List<CategoryUsage>>
        >
    with
        $FutureModifier<List<CategoryUsage>>,
        $FutureProvider<List<CategoryUsage>> {
  /// Categories in sort order with their active beds. Invalidate after a write.
  CategoryUsageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'categoryUsageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$categoryUsageHash();

  @$internal
  @override
  $FutureProviderElement<List<CategoryUsage>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CategoryUsage>> create(Ref ref) {
    return categoryUsage(ref);
  }
}

String _$categoryUsageHash() => r'43703adf2baa3b862a37a1cc5384fdc38c93e77e';

/// The settings form as stored. Invalidate after saving.

@ProviderFor(settingsForm)
final settingsFormProvider = SettingsFormProvider._();

/// The settings form as stored. Invalidate after saving.

final class SettingsFormProvider
    extends
        $FunctionalProvider<
          AsyncValue<SettingsInput>,
          SettingsInput,
          FutureOr<SettingsInput>
        >
    with $FutureModifier<SettingsInput>, $FutureProvider<SettingsInput> {
  /// The settings form as stored. Invalidate after saving.
  SettingsFormProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsFormProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsFormHash();

  @$internal
  @override
  $FutureProviderElement<SettingsInput> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SettingsInput> create(Ref ref) {
    return settingsForm(ref);
  }
}

String _$settingsFormHash() => r'b1782c631624f49dae4caa6d68701f17c6853a94';

/// The next receipt number on this device, for the prefix preview.

@ProviderFor(nextReceiptNumber)
final nextReceiptNumberProvider = NextReceiptNumberProvider._();

/// The next receipt number on this device, for the prefix preview.

final class NextReceiptNumberProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// The next receipt number on this device, for the prefix preview.
  NextReceiptNumberProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nextReceiptNumberProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nextReceiptNumberHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return nextReceiptNumber(ref);
  }
}

String _$nextReceiptNumberHash() => r'c93ec266b8f83e9fbd86073f61bfa464b07002d8';
