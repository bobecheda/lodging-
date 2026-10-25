import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/auth/user_account.dart';
import '../../auth/domain/credentials.dart';
import '../../payments/domain/payment_rules.dart';
import '../../shifts/domain/shift_rules.dart';
import '../domain/owner_more.dart';
import 'owner_cloud.dart';
import 'owner_rows.dart';

/// A shift as More → Shifts shows it.
final class OwnerShift {
  const OwnerShift({
    required this.id,
    required this.userName,
    required this.openedAt,
    required this.openingFloat,
    this.closedAt,
    this.takings,
    this.expectedCash,
    this.expectedPaybill,
    this.countedCash,
    this.variance,
    this.closeNote,
    this.closedBy,
  });

  final String id;
  final String userName;
  final DateTime openedAt;
  final int openingFloat;

  /// Null while open.
  final DateTime? closedAt;

  /// While open: what it has taken so far (the desk's `takingsFrom`).
  final ShiftTakings? takings;

  // When closed, as the desk counted it.
  final int? expectedCash;
  final int? expectedPaybill;
  final int? countedCash;
  final int? variance;
  final String? closeNote;
  final String? closedBy;

  bool get open => closedAt == null;
}

/// A user as More → Staff shows them.
final class OwnerStaffMember {
  const OwnerStaffMember({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    required this.active,
  });

  final String id;
  final String name;
  final String username;
  final Role role;
  final bool active;
}

/// One audit entry as More → Audit trail shows it.
final class OwnerAuditEntry {
  const OwnerAuditEntry({
    required this.at,
    required this.who,
    required this.action,
    required this.where,
    this.detail,
  });

  final DateTime at;
  final String who;
  final String action;

  /// "on the desk" or "on the phone".
  final String where;

  /// Only for allowed entities ([auditDetailEntities]) and refunds.
  final String? detail;
}

/// The audit trail's filters.
final class AuditFilter {
  const AuditFilter({this.userId, this.kind, this.since});
  final String? userId;
  final AuditKind? kind;

  /// UTC; null: all time.
  final DateTime? since;

  @override
  bool operator ==(Object other) =>
      other is AuditFilter &&
      other.userId == userId &&
      other.kind == kind &&
      other.since == since;

  @override
  int get hashCode => Object.hash(userId, kind, since);
}

/// A password change the phone refused; [message] is shown.
final class OwnerPasswordRefused implements Exception {
  const OwnerPasswordRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// More on the owner's phone (owner-app-3): Shifts, the Audit trail and
/// Staff, read-only and column by column; and the owner's password change.
class OwnerMoreRepository {
  OwnerMoreRepository(this._cloud);

  final OwnerCloud _cloud;

  /// How many audit entries are shown, newest first.
  static const auditShown = 200;

  /// The open shifts and those opened since [since], newest first.
  Future<List<OwnerShift>> shifts(DateTime since) async {
    final users = await loadUsers(_cloud);
    String name(String? id) => id == null ? '—' : users[id]?.name ?? '—';
    const columns = [
      'id',
      'user_id',
      'opened_at',
      'closed_at',
      'status',
      'opening_float',
      'expected_cash',
      'expected_paybill',
      'counted_cash',
      'variance',
      'close_note',
      'closed_by',
    ];
    final byId = {
      for (final s in [
        ...await _cloud.rows(
          'shifts',
          columns,
          where: const [Eq('status', 'open')],
        ),
        ...await _cloud.rows(
          'shifts',
          columns,
          where: [Gte('opened_at', since.toIso8601String())],
        ),
      ])
        s.str('id'): s,
    };
    final openIds = [
      for (final s in byId.values)
        if (s.str('status') == 'open') s.str('id'),
    ];
    final payments = openIds.isEmpty
        ? const <Map<String, Object?>>[]
        : await _cloud.rows(
            'payments',
            ['id', 'shift_id', 'amount', 'method'],
            where: [InList('shift_id', openIds)],
          );
    final payouts = openIds.isEmpty
        ? const <Map<String, Object?>>[]
        : await _cloud.rows(
            'refunds',
            ['id', 'shift_id', 'amount', 'method'],
            where: [InList('shift_id', openIds)],
          );
    final voids = openIds.isEmpty
        ? const <Map<String, Object?>>[]
        : await _cloud.rows('voids', ['target_type', 'target_id']);
    Set<String> voided(String type) => {
      for (final v in voids)
        if (v.str('target_type') == type) v.str('target_id'),
    };
    MoneyLine line(Map<String, Object?> r) => (
      id: r.str('id'),
      amount: r.integer('amount'),
      method: PaymentMethod.parse(r.str('method')),
    );
    final shifts = [
      for (final s in byId.values)
        OwnerShift(
          id: s.str('id'),
          userName: name(s.str('user_id')),
          openedAt: s.time('opened_at'),
          openingFloat: s.integer('opening_float'),
          closedAt: s.timeOrNull('closed_at'),
          takings: s.str('status') == 'open'
              ? takingsFrom(
                  payments: [
                    for (final p in payments)
                      if (p.str('shift_id') == s.str('id')) line(p),
                  ],
                  refundPayouts: [
                    for (final r in payouts)
                      if (r.str('shift_id') == s.str('id')) line(r),
                  ],
                  voidedPaymentIds: voided('payment'),
                  voidedRefundIds: voided('refund'),
                )
              : null,
          expectedCash: s.intOrNull('expected_cash'),
          expectedPaybill: s.intOrNull('expected_paybill'),
          countedCash: s.intOrNull('counted_cash'),
          variance: s.intOrNull('variance'),
          closeNote: s.strOrNull('close_note'),
          closedBy: s.strOrNull('closed_by') == null
              ? null
              : name(s.strOrNull('closed_by')),
        ),
    ];
    return shifts..sort((a, b) {
      if (a.open != b.open) return a.open ? -1 : 1;
      return b.openedAt.compareTo(a.openedAt);
    });
  }

  /// Everyone on the desk (never `password_hash`), owner first.
  Future<List<OwnerStaffMember>> staff() async {
    final rows = await _cloud.rows('users', [
      'id',
      'full_name',
      'username',
      'role',
      'is_active',
    ]);
    final list = [
      for (final u in rows)
        OwnerStaffMember(
          id: u.str('id'),
          name: u.str('full_name'),
          username: u.str('username'),
          role: Role.parse(u.str('role')),
          active: u['is_active']! as bool,
        ),
    ];
    return list..sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      return byRole != 0 ? byRole : a.name.compareTo(b.name);
    });
  }

  /// The latest [auditShown] entries matching [filter], newest first;
  /// [deskIds] are the desks' device ids ("on the desk").
  Future<List<OwnerAuditEntry>> audit(
    AuditFilter filter, {
    required Set<String> deskIds,
  }) async {
    final users = await loadUsers(_cloud);
    final kind = filter.kind;
    final userId = filter.userId;
    final since = filter.since;
    final entries = await _cloud.rows(
      'audit_log',
      ['id', 'at', 'user_id', 'action', 'entity', 'entity_id', 'device_id'],
      where: [
        if (userId != null) Eq('user_id', userId),
        if (kind != null) InList('action', auditActionsOf(kind)),
        if (since != null) Gte('at', since.toIso8601String()),
      ],
      orderBy: 'at',
      newestFirst: true,
      limit: auditShown,
    );
    // Details: before/after only of the allowed entities.
    final detailIds = [
      for (final e in entries)
        if (auditDetailEntities.contains(e.str('entity'))) e.str('id'),
    ];
    final details = detailIds.isEmpty
        ? const <String, Map<String, Object?>>{}
        : {
            for (final d in await _cloud.rows(
              'audit_log',
              ['id', 'before_json', 'after_json'],
              where: [
                InList('entity', auditDetailEntities.toList()),
                InList('id', detailIds),
              ],
            ))
              d.str('id'): d,
          };
    // Refunds: their own named columns, never their rows' JSON.
    final refundIds = [
      for (final e in entries)
        if (e.str('entity') == 'refunds') e.str('entity_id'),
    ];
    final refunds = refundIds.isEmpty
        ? const <String, Map<String, Object?>>{}
        : {
            for (final r in await _cloud.rows(
              'refunds',
              ['id', 'amount', 'method', 'paid_at'],
              where: [InList('id', refundIds)],
            ))
              r.str('id'): r,
          };
    final decisions = refundIds.isEmpty
        ? const <String, String>{}
        : {
            for (final d in await _cloud.rows(
              'refund_decisions',
              ['refund_id', 'decision'],
              where: [InList('refund_id', refundIds)],
            ))
              d.str('refund_id'): d.str('decision'),
          };
    String? detailOf(Map<String, Object?> e) {
      final entity = e.str('entity');
      if (entity == 'refunds') {
        final r = refunds[e.str('entity_id')];
        if (r == null) return null;
        final paid = r.strOrNull('paid_at') != null;
        final method = r.strOrNull('method');
        return refundDetail(
          amount: r.integer('amount'),
          method: method == null ? null : PaymentMethod.parse(method),
          status: paid
              ? 'Paid'
              : switch (decisions[r.str('id')]) {
                  'approved' => 'Approved',
                  'rejected' => 'Rejected',
                  _ => 'Waiting',
                },
        );
      }
      final d = details[e.str('id')];
      if (d == null) return null;
      return auditDetail(
        entity: entity,
        action: e.str('action'),
        before: d.strOrNull('before_json'),
        after: d.strOrNull('after_json'),
      );
    }

    return [
      for (final e in entries)
        OwnerAuditEntry(
          at: e.time('at'),
          who: e.strOrNull('user_id') == null
              ? 'Someone'
              : users[e.str('user_id')]?.name ?? '—',
          action: auditLabel(e.str('action')),
          where: whereDone(e.str('device_id'), deskIds: deskIds),
          detail: detailOf(e),
        ),
    ];
  }

  /// The owner changes their password on the phone (owner-app-3): the
  /// current one checked, the change recorded (`user.change_password`,
  /// the server's time), then set, then the owner's other sessions ended
  /// (the desk's owner sign-in; its sync goes on). Recorded first: if
  /// setting it fails, the desk only asks for one online sign-in, which the
  /// unchanged password passes. Throws [OwnerPasswordRefused],
  /// [OwnerCloudOffline] or [OwnerSignInRefused].
  Future<void> changePassword(
    UserAccount owner, {
    required String current,
    required String next,
  }) async {
    final problem = passwordError(next);
    if (problem != null) throw OwnerPasswordRefused(problem);
    if (next == current) {
      throw const OwnerPasswordRefused(
        'Choose a password different from the current one.',
      );
    }
    try {
      await _cloud.verifyPassword(current);
    } on OwnerSignInRefused {
      throw const OwnerPasswordRefused('That isn’t your current password.');
    }
    final at = (await _cloud.rpc('server_time', const {}))! as String;
    final device = await _cloud.deviceId();
    final id = const Uuid().v4();
    await _cloud.rpc('record_password_change', {
      'p_id': id,
      'p_device_id': device,
      'p_audit': [
        {
          'id': const Uuid().v4(),
          'created_at': at,
          'updated_at': at,
          'device_id': device,
          'at': at,
          'operation_id': const Uuid().v4(),
          'user_id': owner.id,
          'action': 'user.change_password',
          'entity': 'users',
          'entity_id': owner.id,
          'before_json': null,
          'after_json': jsonEncode({'id': owner.id}),
        },
      ],
    });
    try {
      await _cloud.updatePassword(next);
    } on OwnerCloudRefused catch (e) {
      throw OwnerPasswordRefused(
        'The new password wasn’t saved (${e.message}). Try again.',
      );
    }
    await _cloud.signOutOtherSessions();
  }
}
