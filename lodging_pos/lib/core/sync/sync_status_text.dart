/// The sync pill's words and tone (docs/design.md, "Sync pill"). Pure.
library;

import '../clock/nairobi.dart';
import '../money/kes.dart';
import 'sync_engine.dart';

enum SyncTone { calm, waiting, problem }

SyncTone syncTone(SyncPhase phase) => switch (phase) {
  SyncPhase.online || SyncPhase.uploading => SyncTone.calm,
  SyncPhase.problem => SyncTone.problem,
  _ => SyncTone.waiting,
};

/// `just now`, `4 min ago`, `3 h ago`, then the date (`Thu 15 Oct`).
String syncAgo(DateTime at, DateTime now) {
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours} h ago';
  return formatDayDate(at);
}

String _waiting(int pending) =>
    '${formatKesPlain(pending)} ${pending == 1 ? 'change' : 'changes'} waiting';

/// "Online · synced 2 min ago", "Offline · 14 changes waiting",
/// "Sync problem · details", "Uploading 3,400 of 12,880", …
String syncPillText(
  SyncStatus status, {
  required int pending,
  required DateTime now,
}) => switch (status.phase) {
  SyncPhase.notConfigured => 'Sync not set up · ${_waiting(pending)}',
  SyncPhase.notConnected => 'Not connected · ${_waiting(pending)}',
  SyncPhase.uploading =>
    'Uploading ${formatKesPlain(status.uploadSent)} of '
        '${formatKesPlain(status.uploadTotal)}',
  SyncPhase.waitingForOwner => 'First upload · owner sign-in needed',
  SyncPhase.online =>
    'Online · synced '
        '${status.lastSyncAt == null ? 'just now' : syncAgo(status.lastSyncAt!, now)}',
  SyncPhase.offline => 'Offline · ${_waiting(pending)}',
  SyncPhase.problem => 'Sync problem · details',
};
