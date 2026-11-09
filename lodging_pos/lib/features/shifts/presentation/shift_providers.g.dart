// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shift_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(shiftRepository)
final shiftRepositoryProvider = ShiftRepositoryProvider._();

final class ShiftRepositoryProvider
    extends
        $FunctionalProvider<ShiftRepository, ShiftRepository, ShiftRepository>
    with $Provider<ShiftRepository> {
  ShiftRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shiftRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shiftRepositoryHash();

  @$internal
  @override
  $ProviderElement<ShiftRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ShiftRepository create(Ref ref) {
    return shiftRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShiftRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShiftRepository>(value),
    );
  }
}

String _$shiftRepositoryHash() => r'a14bc8d89bcd8cb289bb77a3c597ebfae2adc695';

/// The open shift on this device, if any.

@ProviderFor(CurrentShift)
final currentShiftProvider = CurrentShiftProvider._();

/// The open shift on this device, if any.
final class CurrentShiftProvider
    extends $AsyncNotifierProvider<CurrentShift, OpenShift?> {
  /// The open shift on this device, if any.
  CurrentShiftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentShiftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentShiftHash();

  @$internal
  @override
  CurrentShift create() => CurrentShift();
}

String _$currentShiftHash() => r'380c322c01bd2f11887c9ca34aa87b32256a8728';

/// The open shift on this device, if any.

abstract class _$CurrentShift extends $AsyncNotifier<OpenShift?> {
  FutureOr<OpenShift?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<OpenShift?>, OpenShift?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OpenShift?>, OpenShift?>,
              AsyncValue<OpenShift?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the signed-in receptionist has continued (or opened) their shift
/// in this sign-in. Resets on every sign-in, so returning to an open shift
/// always shows the resume card first.

@ProviderFor(ShiftContinued)
final shiftContinuedProvider = ShiftContinuedProvider._();

/// Whether the signed-in receptionist has continued (or opened) their shift
/// in this sign-in. Resets on every sign-in, so returning to an open shift
/// always shows the resume card first.
final class ShiftContinuedProvider
    extends $NotifierProvider<ShiftContinued, bool> {
  /// Whether the signed-in receptionist has continued (or opened) their shift
  /// in this sign-in. Resets on every sign-in, so returning to an open shift
  /// always shows the resume card first.
  ShiftContinuedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shiftContinuedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shiftContinuedHash();

  @$internal
  @override
  ShiftContinued create() => ShiftContinued();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$shiftContinuedHash() => r'cc3f29cc007f479e421e60f0636efb0b657774c6';

/// Whether the signed-in receptionist has continued (or opened) their shift
/// in this sign-in. Resets on every sign-in, so returning to an open shift
/// always shows the resume card first.

abstract class _$ShiftContinued extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the drawer has been counted at least once (the starting cash).

@ProviderFor(drawerStarted)
final drawerStartedProvider = DrawerStartedProvider._();

/// Whether the drawer has been counted at least once (the starting cash).

final class DrawerStartedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the drawer has been counted at least once (the starting cash).
  DrawerStartedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'drawerStartedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$drawerStartedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return drawerStarted(ref);
  }
}

String _$drawerStartedHash() => r'7080925121f5c318dcf71602984a9a8bf42f0521';

/// Where [shiftId]'s close is (first count, recount, reason), from the shift
/// itself.

@ProviderFor(closeStage)
final closeStageProvider = CloseStageFamily._();

/// Where [shiftId]'s close is (first count, recount, reason), from the shift
/// itself.

final class CloseStageProvider
    extends
        $FunctionalProvider<
          AsyncValue<CountStage>,
          CountStage,
          FutureOr<CountStage>
        >
    with $FutureModifier<CountStage>, $FutureProvider<CountStage> {
  /// Where [shiftId]'s close is (first count, recount, reason), from the shift
  /// itself.
  CloseStageProvider._({
    required CloseStageFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'closeStageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$closeStageHash();

  @override
  String toString() {
    return r'closeStageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CountStage> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<CountStage> create(Ref ref) {
    final argument = this.argument as String;
    return closeStage(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CloseStageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$closeStageHash() => r'723ad26e212657359cef8e6a4a565970447f3f23';

/// Where [shiftId]'s close is (first count, recount, reason), from the shift
/// itself.

final class CloseStageFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CountStage>, String> {
  CloseStageFamily._()
    : super(
        retry: null,
        name: r'closeStageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Where [shiftId]'s close is (first count, recount, reason), from the shift
  /// itself.

  CloseStageProvider call(String shiftId) =>
      CloseStageProvider._(argument: shiftId, from: this);

  @override
  String toString() => r'closeStageProvider';
}

/// What the drawer should hold now, for [viewShiftTotals] users only; null
/// for anyone else and before any count.

@ProviderFor(drawerNow)
final drawerNowProvider = DrawerNowProvider._();

/// What the drawer should hold now, for [viewShiftTotals] users only; null
/// for anyone else and before any count.

final class DrawerNowProvider
    extends $FunctionalProvider<AsyncValue<int?>, int?, FutureOr<int?>>
    with $FutureModifier<int?>, $FutureProvider<int?> {
  /// What the drawer should hold now, for [viewShiftTotals] users only; null
  /// for anyone else and before any count.
  DrawerNowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'drawerNowProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$drawerNowHash();

  @$internal
  @override
  $FutureProviderElement<int?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int?> create(Ref ref) {
    return drawerNow(ref);
  }
}

String _$drawerNowHash() => r'e70d69b6bc4234e67a88e2118a6efa5d8fa00859';

/// The drawer's chain, newest first, for [viewShiftTotals] users only.

@ProviderFor(drawerChain)
final drawerChainProvider = DrawerChainProvider._();

/// The drawer's chain, newest first, for [viewShiftTotals] users only.

final class DrawerChainProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ChainEntry>>,
          List<ChainEntry>,
          Stream<List<ChainEntry>>
        >
    with $FutureModifier<List<ChainEntry>>, $StreamProvider<List<ChainEntry>> {
  /// The drawer's chain, newest first, for [viewShiftTotals] users only.
  DrawerChainProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'drawerChainProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$drawerChainHash();

  @$internal
  @override
  $StreamProviderElement<List<ChainEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ChainEntry>> create(Ref ref) {
    return drawerChain(ref);
  }
}

String _$drawerChainHash() => r'93f10763fa6a8fdc0f8f8bbf8658cb1ab3dd0a71';

/// The supervisor's list of shifts (FD-11), watched.

@ProviderFor(shiftList)
final shiftListProvider = ShiftListProvider._();

/// The supervisor's list of shifts (FD-11), watched.

final class ShiftListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ShiftSummary>>,
          List<ShiftSummary>,
          Stream<List<ShiftSummary>>
        >
    with
        $FutureModifier<List<ShiftSummary>>,
        $StreamProvider<List<ShiftSummary>> {
  /// The supervisor's list of shifts (FD-11), watched.
  ShiftListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shiftListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shiftListHash();

  @$internal
  @override
  $StreamProviderElement<List<ShiftSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ShiftSummary>> create(Ref ref) {
    return shiftList(ref);
  }
}

String _$shiftListHash() => r'84f439c2c423d2f1a49accf295a6e18ca1f9d104';

/// An open shift by id, for closing someone else's (FD-11).

@ProviderFor(openShiftById)
final openShiftByIdProvider = OpenShiftByIdFamily._();

/// An open shift by id, for closing someone else's (FD-11).

final class OpenShiftByIdProvider
    extends
        $FunctionalProvider<
          AsyncValue<OpenShift?>,
          OpenShift?,
          FutureOr<OpenShift?>
        >
    with $FutureModifier<OpenShift?>, $FutureProvider<OpenShift?> {
  /// An open shift by id, for closing someone else's (FD-11).
  OpenShiftByIdProvider._({
    required OpenShiftByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'openShiftByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$openShiftByIdHash();

  @override
  String toString() {
    return r'openShiftByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<OpenShift?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<OpenShift?> create(Ref ref) {
    final argument = this.argument as String;
    return openShiftById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OpenShiftByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$openShiftByIdHash() => r'af9ba93b7f2ee0f9aeaa8112927558f3571ac17e';

/// An open shift by id, for closing someone else's (FD-11).

final class OpenShiftByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<OpenShift?>, String> {
  OpenShiftByIdFamily._()
    : super(
        retry: null,
        name: r'openShiftByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// An open shift by id, for closing someone else's (FD-11).

  OpenShiftByIdProvider call(String shiftId) =>
      OpenShiftByIdProvider._(argument: shiftId, from: this);

  @override
  String toString() => r'openShiftByIdProvider';
}
