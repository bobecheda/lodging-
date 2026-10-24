/// Writes that go to the cloud first once this desk is connected: the
/// owner's decisions and prices, and price request withdrawals (BR-2,
/// BR-8a). The repository calls one of these, and only when it returns
/// mirrors the same row locally (`writeWithAudit(inCloud: ...)`); the first
/// write to reach the cloud wins. Before the desk is connected,
/// [CloudWrites.active] is false and everything stays local as before.
library;

import '../clock/nairobi.dart';
import 'cloud.dart' show PriceEdit;

export 'cloud.dart' show PriceEdit;

abstract interface class CloudWrites {
  /// Connected: these writes need the cloud.
  bool get active;

  Future<void> decideRefund({
    required String id,
    required String refundId,
    required bool approve,
    required String? note,
    required DateTime at,
  });

  Future<void> decidePriceRequest({
    required String id,
    required String requestId,
    required bool approve,
    required String? note,
    required DateTime at,
  });

  /// The owner's new prices, each over the price it started from; refused
  /// with [PriceChangedElsewhere] when one moved on in the cloud.
  Future<void> changePrices(List<PriceEdit> edits, DateTime at);

  Future<void> withdrawPriceRequest({
    required String requestId,
    required String by,
    required String? reason,
    required DateTime at,
  });
}

/// Why a cloud-first write didn't happen. Repositories turn these into
/// their own rule messages ("Approving needs an internet connection.").
sealed class CloudWriteRefused implements Exception {
  const CloudWriteRefused();
}

/// No internet, or the cloud is down.
final class NeedsInternet extends CloudWriteRefused {
  const NeedsInternet();
}

/// The owner's cloud sign-in is missing (signed in on the desk offline, or
/// it lapsed): the screen asks for the password and tries again.
final class OwnerCloudSignInNeeded extends CloudWriteRefused {
  const OwnerCloudSignInNeeded();
}

/// Connected, but the first upload hasn't finished.
final class FirstUploadUnfinished extends CloudWriteRefused {
  const FirstUploadUnfinished();
}

/// The queue is stopped at a refused row, so this desk's latest changes
/// aren't in the cloud to decide on.
final class SyncBlocked extends CloudWriteRefused {
  const SyncBlocked(this.problem);
  final String problem;
}

/// The cloud refused the write itself (a rule); [message] says why.
final class RefusedByCloud extends CloudWriteRefused {
  const RefusedByCloud(this.message);
  final String message;
}

/// Someone decided first ("Already decided by Amina Owner · 10:42").
final class DecidedElsewhere extends CloudWriteRefused {
  const DecidedElsewhere({
    required this.approved,
    required this.byName,
    required this.at,
  });

  final bool approved;
  final String? byName;
  final DateTime at;
}

/// The price request was withdrawn first.
final class WithdrawnElsewhere extends CloudWriteRefused {
  const WithdrawnElsewhere();
}

/// The category's price in the cloud has moved on from the request.
final class StaleElsewhere extends CloudWriteRefused {
  const StaleElsewhere(this.currentPrice);
  final int currentPrice;
}

/// Another price edit (the phone's, or another desk's) got to the cloud
/// first; nothing was saved. The caller words it with the category's name
/// ([priceMovedOnMessage]).
final class PriceChangedElsewhere extends CloudWriteRefused {
  const PriceChangedElsewhere({
    required this.categoryId,
    required this.currentPrice,
    required this.at,
    required this.changedOn,
  });

  final String categoryId;
  final int currentPrice;
  final DateTime at;

  /// `desk`, `phone`, or null.
  final String? changedOn;
}

/// The sentence a screen shows for [refusal]; [needsInternet] names the
/// action ("Approving needs an internet connection."). Not for
/// [OwnerCloudSignInNeeded] (the screen asks for the password) or
/// [StaleElsewhere] (the caller words it).
String cloudRefusalMessage(
  CloudWriteRefused refusal, {
  required String needsInternet,
}) => switch (refusal) {
  NeedsInternet() => needsInternet,
  FirstUploadUnfinished() =>
    'The first upload to the cloud isn’t finished yet. Try again once it is.',
  SyncBlocked(:final problem) =>
    'Sync has a problem, so this can’t be done yet: $problem',
  RefusedByCloud(:final message) => message,
  DecidedElsewhere(:final approved, :final byName, :final at) =>
    'Already decided by ${byName ?? 'someone else'} · '
        '${formatDayDateComma(at)} (${approved ? 'approved' : 'rejected'}).',
  WithdrawnElsewhere() => 'This request was withdrawn.',
  StaleElsewhere(:final currentPrice) =>
    'The price is now KES $currentPrice in the cloud.',
  PriceChangedElsewhere(:final currentPrice) =>
    'The price is now KES $currentPrice in the cloud. Check it and save '
        'again.',
  OwnerCloudSignInNeeded() => 'Sign in to the cloud again to continue.',
};
