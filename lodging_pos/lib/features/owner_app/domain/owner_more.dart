/// More on the owner's phone (owner-app-3): the audit trail in words, the
/// details the phone may show, shifts' differences, and the desk's last
/// sync. Pure Dart.
library;

import 'dart:convert';

import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../payments/domain/payment_rules.dart';
import 'owner_today.dart';

// ── The audit trail ──────────────────────────────────────────────────────

/// The audit trail's filter kinds.
enum AuditKind {
  money('Money'),
  stays('Stays'),
  prices('Prices'),
  staff('Staff'),
  signIns('Sign-ins'),
  other('Other');

  const AuditKind(this.label);
  final String label;
}

/// Every audit action (CLAUDE.md, "Audit actions") in words, with its kind.
const _actions = <String, (String, AuditKind)>{
  'payment.create': ('Took a payment', AuditKind.money),
  'payment.print': ('Printed a receipt', AuditKind.money),
  'refund.request': ('Asked for a refund', AuditKind.money),
  'refund.approve': ('Approved a refund', AuditKind.money),
  'refund.reject': ('Rejected a refund', AuditKind.money),
  'refund.pay': ('Paid out a refund', AuditKind.money),
  'refund.print': ('Printed a REFUND receipt', AuditKind.money),
  'void.create': ('Voided a record', AuditKind.money),
  'shift.open': ('Opened a shift', AuditKind.money),
  'shift.close': ('Closed a shift', AuditKind.money),
  'stay.check_in': ('Checked a guest in', AuditKind.stays),
  'stay.extend': ('Extended a stay', AuditKind.stays),
  'stay.late_charge': ('Charged a late checkout', AuditKind.stays),
  'stay.check_out': ('Checked a guest out', AuditKind.stays),
  'guest.create': ('Registered a guest', AuditKind.stays),
  'guest.update': ('Corrected a guest', AuditKind.stays),
  'bed.mark_clean': ('Marked a bed clean', AuditKind.stays),
  'housekeeping.assign': ('Assigned a cleaning', AuditKind.stays),
  'housekeeping.reassign': ('Reassigned a cleaning', AuditKind.stays),
  'housekeeping.cancel': ('Cancelled a cleaning', AuditKind.stays),
  'room.create': ('Added a room', AuditKind.stays),
  'room.update': ('Changed a room', AuditKind.stays),
  'room.deactivate': ('Closed a room', AuditKind.stays),
  'room.reactivate': ('Reopened a room', AuditKind.stays),
  'bed.create': ('Added a bed', AuditKind.stays),
  'bed.update': ('Changed a bed', AuditKind.stays),
  'bed.deactivate': ('Closed a bed', AuditKind.stays),
  'bed.reactivate': ('Reopened a bed', AuditKind.stays),
  'price.update': ('Changed a price', AuditKind.prices),
  'price.request': ('Asked for a price change', AuditKind.prices),
  'price.request_withdraw': ('Withdrew a price request', AuditKind.prices),
  'price.approve': ('Approved a price change', AuditKind.prices),
  'price.reject': ('Rejected a price change', AuditKind.prices),
  'category.create': ('Added a category', AuditKind.prices),
  'category.update': ('Changed a category', AuditKind.prices),
  'user.create': ('Added a user', AuditKind.staff),
  'user.disable': ('Disabled a user', AuditKind.staff),
  'user.enable': ('Enabled a user', AuditKind.staff),
  'user.reset_password': ('Reset a password', AuditKind.staff),
  'user.change_password': ('Changed their password', AuditKind.staff),
  'user.password_from_cloud': (
    'Desk took the password set on the phone',
    AuditKind.staff,
  ),
  'housekeeper.create': ('Added a housekeeper', AuditKind.staff),
  'housekeeper.update': ('Changed a housekeeper', AuditKind.staff),
  'housekeeper.deactivate': ('Removed a housekeeper', AuditKind.staff),
  'housekeeper.reactivate': ('Brought back a housekeeper', AuditKind.staff),
  'user.login': ('Signed in', AuditKind.signIns),
  'user.login_failed': ('Failed to sign in', AuditKind.signIns),
  'user.auto_lock': ('Screen locked (idle)', AuditKind.signIns),
  'user.lock': ('Locked the screen', AuditKind.signIns),
  'settings.update': ('Changed a setting', AuditKind.other),
  'backup.create': ('Backed up', AuditKind.other),
  'backup.failed': ('Backup failed', AuditKind.other),
  'sync.connect': ('Connected the desk to the cloud', AuditKind.other),
  'sync.reconnect': ('Reconnected the desk', AuditKind.other),
  'sync.first_upload': ('Sent everything to the cloud', AuditKind.other),
  'sync.clock_warning': ('The desk’s clock was wrong', AuditKind.other),
};

/// "Checked a guest in"; an action this app doesn't know reads as itself.
String auditLabel(String action) => _actions[action]?.$1 ?? action;

AuditKind auditKindOf(String action) => _actions[action]?.$2 ?? AuditKind.other;

/// The actions of [kind], for the filter.
List<String> auditActionsOf(AuditKind kind) => [
  for (final MapEntry(:key, :value) in _actions.entries)
    if (value.$2 == kind) key,
];

/// The only entities whose before/after details the phone reads: none holds
/// guest data. `refunds` is left out (its rows carry `payout_phone`); a
/// refund's detail comes from the refund's own named columns instead
/// ([refundDetail]). test/policy/owner_app_test.dart holds the phone to it.
const auditDetailEntities = {
  'bed_categories',
  'refund_decisions',
  'price_decisions',
  'voids',
  'shifts',
};

Map<String, Object?> _json(String? text) {
  if (text == null || text.isEmpty) return const {};
  try {
    final v = jsonDecode(text);
    return v is Map<String, Object?> ? v : const {};
  } on FormatException {
    return const {};
  }
}

String _decision(Map<String, Object?> after) {
  final decided = after['decision'] == 'approved' ? 'Approved' : 'Rejected';
  final note = after['note'];
  return note is String && note.isNotEmpty ? '$decided · “$note”' : decided;
}

/// One line of detail for an entry of an allowed entity
/// ([auditDetailEntities]), read as named keys; null for anything else.
String? auditDetail({
  required String entity,
  required String action,
  required String? before,
  required String? after,
}) {
  if (!auditDetailEntities.contains(entity)) return null;
  final a = _json(after);
  final b = _json(before);
  switch (entity) {
    case 'bed_categories':
      final name = a['name'] ?? b['name'];
      final from = b['price_per_night'];
      final to = a['price_per_night'];
      if (from is! num || to is! num) return name is String ? name : null;
      final change = '${formatKes(from.toInt())} → ${formatKes(to.toInt())}';
      return name is String ? '$name: $change' : change;
    case 'refund_decisions' || 'price_decisions':
      return a.containsKey('decision') ? _decision(a) : null;
    case 'voids':
      final type = '${a['target_type'] ?? 'record'}';
      final kind = '${type[0].toUpperCase()}${type.substring(1)}';
      final reason = a['reason'];
      return reason is String ? '$kind voided · “$reason”' : '$kind voided';
    case 'shifts':
      if (a['counted_cash'] case final num counted) {
        final variance = a['variance'];
        return 'Counted ${formatKes(counted.toInt())}'
            '${variance is num ? ' · ${varianceLine(variance.toInt())}' : ''}';
      }
      if (a['opening_float'] case final num float) {
        return 'Float ${formatKes(float.toInt())}';
      }
      return null;
  }
  return null;
}

/// A refund entry's detail, from the refund's own columns: "KES 1,400 ·
/// Paid · Cash".
String refundDetail({
  required int amount,
  required PaymentMethod? method,
  required String status,
}) => [formatKes(amount), status, ?method?.label].join(' · ');

/// "on the desk" for a desk's device (one that reports its heartbeat),
/// "on the phone" otherwise.
String whereDone(String deviceId, {required Set<String> deskIds}) =>
    deskIds.contains(deviceId) ? 'on the desk' : 'on the phone';

// ── Shifts ───────────────────────────────────────────────────────────────

/// A closed shift's counted − expected cash, in words, never by colour
/// alone: "KES 300 short", "KES 200 over", "Exact".
String varianceLine(int variance) => switch (variance) {
  0 => 'Exact',
  < 0 => '${formatKes(-variance)} short',
  _ => '${formatKes(variance)} over',
};

// ── The account card ─────────────────────────────────────────────────────

/// "Desk last synced 2 min ago" (Figma "07 More"), from the desk heard
/// from last.
String deskSyncedLine(List<DeskStatus> desks, DateTime now) {
  if (desks.isEmpty) return 'The desk isn’t connected to the cloud yet.';
  final d = desks.reduce((a, b) => b.reportedAt.isAfter(a.reportedAt) ? b : a);
  final pushed = d.lastPushAt;
  if (pushed == null) return 'The desk hasn’t synced yet.';
  final minutes = now.difference(pushed).inMinutes;
  if (minutes < 1) return 'Desk last synced just now';
  if (minutes < 60) return 'Desk last synced $minutes min ago';
  return 'Desk last synced ${formatWhen(pushed, now: now)}';
}
