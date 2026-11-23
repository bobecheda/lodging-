// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reduce_motion.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reduceMotionSetting)
final reduceMotionSettingProvider = ReduceMotionSettingProvider._();

final class ReduceMotionSettingProvider
    extends
        $FunctionalProvider<
          ReduceMotionSetting,
          ReduceMotionSetting,
          ReduceMotionSetting
        >
    with $Provider<ReduceMotionSetting> {
  ReduceMotionSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reduceMotionSettingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reduceMotionSettingHash();

  @$internal
  @override
  $ProviderElement<ReduceMotionSetting> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReduceMotionSetting create(Ref ref) {
    return reduceMotionSetting(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReduceMotionSetting value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReduceMotionSetting>(value),
    );
  }
}

String _$reduceMotionSettingHash() =>
    r'c2741122a395c1702bc2c6b4a5ee8f533b22a17c';

/// Whether this desk has motion turned off. Invalidate after [set].

@ProviderFor(reduceMotion)
final reduceMotionProvider = ReduceMotionProvider._();

/// Whether this desk has motion turned off. Invalidate after [set].

final class ReduceMotionProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether this desk has motion turned off. Invalidate after [set].
  ReduceMotionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reduceMotionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reduceMotionHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return reduceMotion(ref);
  }
}

String _$reduceMotionHash() => r'80fd52bb96dffa964f41369b71a45d664655677f';
