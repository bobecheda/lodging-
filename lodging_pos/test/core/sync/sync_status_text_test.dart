import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_status_text.dart';

void main() {
  final now = nairobiInstant(2026, 10, 22, 12);

  String pill(SyncStatus s, {int pending = 0}) =>
      syncPillText(s, pending: pending, now: now);

  test('the pill’s words for each state', () {
    expect(
      pill(const SyncStatus(phase: SyncPhase.notConfigured), pending: 3),
      'Sync not set up · 3 changes waiting',
    );
    expect(
      pill(const SyncStatus(phase: SyncPhase.notConnected), pending: 1),
      'Not connected · 1 change waiting',
    );
    expect(
      pill(
        const SyncStatus(
          phase: SyncPhase.uploading,
          uploadSent: 3400,
          uploadTotal: 12880,
        ),
      ),
      'Uploading 3,400 of 12,880',
    );
    expect(
      pill(const SyncStatus(phase: SyncPhase.waitingForOwner)),
      'First upload · owner sign-in needed',
    );
    expect(
      pill(
        SyncStatus(
          phase: SyncPhase.online,
          lastSyncAt: now.subtract(const Duration(minutes: 2)),
        ),
      ),
      'Online · synced 2 min ago',
    );
    expect(
      pill(const SyncStatus(phase: SyncPhase.offline), pending: 14),
      'Offline · 14 changes waiting',
    );
    expect(
      pill(const SyncStatus(phase: SyncPhase.problem, problem: 'x')),
      'Sync problem · details',
    );
  });

  test('how long ago', () {
    expect(syncAgo(now.subtract(const Duration(seconds: 30)), now), 'just now');
    expect(
      syncAgo(now.subtract(const Duration(minutes: 59)), now),
      '59 min ago',
    );
    expect(syncAgo(now.subtract(const Duration(hours: 3)), now), '3 h ago');
    expect(syncAgo(nairobiInstant(2026, 10, 15, 9), now), 'Thu 15 Oct');
  });

  test('tones: calm, waiting, problem', () {
    expect(syncTone(SyncPhase.online), SyncTone.calm);
    expect(syncTone(SyncPhase.uploading), SyncTone.calm);
    expect(syncTone(SyncPhase.offline), SyncTone.waiting);
    expect(syncTone(SyncPhase.notConnected), SyncTone.waiting);
    expect(syncTone(SyncPhase.problem), SyncTone.problem);
  });
}
