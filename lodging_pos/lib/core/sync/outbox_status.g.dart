// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbox_status.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Changes written on this desk and not yet sent to the cloud (unsent
/// outbox rows). Sync arrives in sprint 2; until then this only grows.

@ProviderFor(pendingChanges)
final pendingChangesProvider = PendingChangesProvider._();

/// Changes written on this desk and not yet sent to the cloud (unsent
/// outbox rows). Sync arrives in sprint 2; until then this only grows.

final class PendingChangesProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// Changes written on this desk and not yet sent to the cloud (unsent
  /// outbox rows). Sync arrives in sprint 2; until then this only grows.
  PendingChangesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingChangesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingChangesHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return pendingChanges(ref);
  }
}

String _$pendingChangesHash() => r'a760b10e942cea44cdc9d11863002bbdc4166dd0';
