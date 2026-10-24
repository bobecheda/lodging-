/// The sync pill's words and tone (docs/design.md, "Sync pill"). Pure.
library;

import '../clock/nairobi.dart';
import '../money/kes.dart';
import 'sync_engine.dart';

enum SyncTone { calm, waiting, problem }

/// The pill's tone; a clock warning shows (in butter) only while online.
SyncTone syncTone(SyncPhase phase, {bool clockWarning = false}) =>
    switch (phase) {
      SyncPhase.online when clockWarning => SyncTone.waiting,
      SyncPhase.online || SyncPhase.uploading => SyncTone.calm,
      SyncPhase.problem => SyncTone.problem,
      _ => SyncTone.waiting,
    };

/// `12 min slow` / `7 min fast`: the PC against the server ([offset] is
/// the PC's clock minus the server's).
String clockGap(Duration offset) {
  final minutes = (offset.inSeconds.abs() / 60).round();
  return '$minutes min ${offset.isNegative ? 'slow' : 'fast'}';
}

/// The Sync panel's full warning, with the fix.
String clockWarningText(Duration offset) =>
    'PC clock is ${clockGap(offset)}. Windows Settings → Time & language → '
    'Sync now';

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
/// "Sync problem · details", "Uploading 3,400 of 12,880",
/// "PC clock 12 min slow · fix", … A sync problem outranks the clock
/// warning, which outranks online; offline keeps the warning for the panel.
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
  SyncPhase.online when status.clockWarning && status.clockOffset != null =>
    'PC clock ${clockGap(status.clockOffset!)} · fix',
  SyncPhase.online =>
    'Online · synced '
        '${status.lastSyncAt == null ? 'just now' : syncAgo(status.lastSyncAt!, now)}',
  SyncPhase.offline => 'Offline · ${_waiting(pending)}',
  SyncPhase.problem => 'Sync problem · details',
};
