import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../../core/sync/cloud_writes.dart';
import '../domain/cash_review.dart';

/// A target's decision, for the chain.
final class ReviewInfo {
  const ReviewInfo({
    required this.decision,
    required this.decidedBy,
    required this.decidedAt,
    this.reason,
  });

  final ReviewDecision decision;

  /// The decider's full name.
  final String decidedBy;
  final DateTime decidedAt;
  final String? reason;

  /// `Approved by Grace Supervisor`, `Rejected by Amina Owner: …`.
  String get line => decision == ReviewDecision.approved
      ? 'Approved by $decidedBy'
      : 'Rejected by $decidedBy: $reason';
}

/// Story B3: approving or rejecting a shift close or drawer count that
/// needs review, once. The rules (`domain/cash_review.dart`) first; once
/// this desk is connected, the cloud first too (`decide_cash_review`: the
/// owner with their cloud sign-in, a supervisor through the desk's), then
/// the same row here, its outbox row already sent. Not connected: here
/// only. Audited `shift.review_approve` / `shift.review_reject` and
/// `drawer.review_approve` / `drawer.review_reject`.
class CashReviewsRepository {
  CashReviewsRepository(this._db, this._audit, {this._cloud});

  final AppDatabase _db;
  final AuditWriter _audit;
  final CloudWrites? _cloud;

  Future<Map<String, UserAccount>> _users() async => {
    for (final u in await _db.select(_db.users).get())
      u.id: UserAccount(
        id: u.id,
        fullName: u.fullName,
        username: u.username,
        role: Role.parse(u.role),
        isActive: u.isActive,
        mustChangePassword: u.mustChangePassword,
      ),
  };

  /// What the rules need about [id], or null if it doesn't exist (or a
  /// shift isn't closed).
  Future<ReviewTarget?> target(ReviewTargetKind kind, String id) async {
    final users = await _users();
    switch (kind) {
      case ReviewTargetKind.shift:
        final s =
            await (_db.select(_db.shifts)
                  ..where((s) => s.id.equals(id) & s.status.equals('closed')))
                .getSingleOrNull();
        if (s == null) return null;
        return ReviewTarget(
          kind: kind,
          id: id,
          needsReview: s.needsReview,
          named: [?users[s.userId], ?users[s.closedBy]],
        );
      case ReviewTargetKind.drawerEvent:
        final d = await (_db.select(
          _db.drawerEvents,
        )..where((d) => d.id.equals(id))).getSingleOrNull();
        if (d == null) return null;
        return ReviewTarget(
          kind: kind,
          id: id,
          needsReview: d.needsReview,
          named: [?users[d.countedBy], ?users[d.presentUser]],
          counter: users[d.countedBy],
        );
    }
  }

  Future<CashReviewRow?> _decision(ReviewTargetKind kind, String id) =>
      (_db.select(_db.cashReviews)..where(
            (r) => r.targetType.equals(kind.code) & r.targetId.equals(id),
          ))
          .getSingleOrNull();

  /// Awaiting, approved, rejected, or no review needed.
  Future<ReviewStatus> statusOf(ReviewTargetKind kind, String id) async {
    final t = await target(kind, id);
    final d = await _decision(kind, id);
    return reviewStatus(
      needsReview: t?.needsReview ?? false,
      decision: d == null ? null : ReviewDecision.parse(d.decision),
    );
  }

  /// Every decision, by `target_type:target_id`, for the chain.
  Future<Map<String, ReviewInfo>> decisions() async {
    final users = await _users();
    return {
      for (final r in await _db.select(_db.cashReviews).get())
        '${r.targetType}:${r.targetId}': ReviewInfo(
          decision: ReviewDecision.parse(r.decision),
          decidedBy: users[r.decidedBy]?.fullName ?? '',
          decidedAt: r.decidedAt,
          reason: r.reason,
        ),
    };
  }

  /// [user] approves or rejects [id] ([reason] required to reject). Throws
  /// [NotPermitted], [CashReviewProblem] or [OwnerCloudSignInNeeded] (the
  /// owner's cloud sign-in lapsed: the screen asks for the password).
  Future<void> decide(
    UserAccount user,
    ReviewTargetKind kind,
    String id, {
    required bool approve,
    String? reason,
  }) async {
    requirePermission(user, Permission.reviewCash);
    final decision = approve
        ? ReviewDecision.approved
        : ReviewDecision.rejected;
    Future<void> check() async {
      final t = await target(kind, id);
      if (t == null) throw const CashReviewProblem('Nothing to review here.');
      final existing = await _decision(kind, id);
      checkReview(
        t,
        by: user,
        decision: decision,
        reason: reason,
        decided: existing == null
            ? null
            : ReviewDecision.parse(existing.decision),
      );
    }

    await check();
    final reviewId = const Uuid().v4();
    final at = _audit.now();
    final why = approve ? null : reason!.trim();
    final cloud = _cloud;
    final inCloud = cloud != null && cloud.active;
    if (inCloud) {
      try {
        await cloud.decideCashReview(
          id: reviewId,
          targetType: kind.code,
          targetId: id,
          approve: approve,
          reason: why,
          decidedBy: user.id,
          asOwner: can(user, Permission.reviewSupervisorCash),
          at: at,
        );
      } on OwnerCloudSignInNeeded {
        rethrow;
      } on CloudWriteRefused catch (e) {
        throw CashReviewProblem(
          cloudRefusalMessage(
            e,
            needsInternet: 'Deciding needs an internet connection.',
          ),
        );
      }
    }
    await _audit.writeWithAudit(
      action: reviewAction(kind, decision),
      userId: user.id,
      inCloud: {if (inCloud) 'cash_reviews'},
      body: (w) async {
        await check();
        await w.insert(
          _db.cashReviews,
          CashReviewsCompanion.insert(
            id: Value(reviewId),
            targetType: kind.code,
            targetId: id,
            decision: decision.code,
            reason: Value(why),
            decidedBy: user.id,
            decidedAt: at,
          ),
        );
      },
    );
  }

  /// Rejections decided at or after [since], newest first, for the owner's
  /// Needs your attention. Needs [Permission.viewShiftTotals].
  Future<List<RejectedReview>> rejectedSince(
    DateTime since, {
    required UserAccount by,
  }) async {
    requirePermission(by, Permission.viewShiftTotals);
    final users = await _users();
    String name(String? id) => users[id]?.fullName ?? '';
    final rows =
        await (_db.select(_db.cashReviews)
              ..where(
                (r) =>
                    r.decision.equals('rejected') &
                    r.decidedAt.isBiggerOrEqualValue(since),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.decidedAt)]))
            .get();
    final out = <RejectedReview>[];
    for (final r in rows) {
      final kind = ReviewTargetKind.parse(r.targetType);
      final String whose;
      final int gap;
      switch (kind) {
        case ReviewTargetKind.shift:
          final s = await (_db.select(
            _db.shifts,
          )..where((s) => s.id.equals(r.targetId))).getSingleOrNull();
          if (s == null) continue;
          whose = '${name(s.userId)}’s shift close';
          gap = s.variance ?? 0;
        case ReviewTargetKind.drawerEvent:
          final d = await (_db.select(
            _db.drawerEvents,
          )..where((d) => d.id.equals(r.targetId))).getSingleOrNull();
          if (d == null) continue;
          whose =
              '${name(d.countedBy)}’s '
              '${d.kind == 'collect' ? 'collection' : 'drawer check'}';
          gap = d.counted - (d.expected ?? d.counted);
      }
      out.add(
        RejectedReview(
          kind: kind,
          targetId: r.targetId,
          whose: whose,
          decidedBy: name(r.decidedBy),
          reason: r.reason ?? '',
          decidedAt: r.decidedAt,
          gap: gap,
        ),
      );
    }
    return out;
  }
}
