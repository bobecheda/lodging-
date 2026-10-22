import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../../core/sync/cloud_writes.dart';
import '../../setup/data/prices_repository.dart' show CategoryRuleViolation;
import '../../setup/domain/bed_category.dart';
import '../domain/price_request.dart';

/// One request as the screens show it: the request, its category as it is
/// now, and who asked and decided.
final class PriceRequestView {
  const PriceRequestView({
    required this.request,
    required this.categoryName,
    required this.currentPrice,
    required this.requestedByName,
    this.requestedByRole,
    this.decidedByName,
  });

  final PriceRequest request;
  final String categoryName;

  /// The category's price now; differs from `request.oldPrice` once the
  /// owner changed it directly.
  final int currentPrice;
  final String requestedByName;
  final Role? requestedByRole;
  final String? decidedByName;

  String get id => request.id;
  PriceRequestStatus get status => request.status;

  /// Waiting, but the price has moved on since: it can only be rejected.
  bool get stale =>
      status == PriceRequestStatus.waiting && currentPrice != request.oldPrice;

  /// "Grace": the requester's first name, as the owner's card names them.
  String get requestedByFirstName => requestedByName.split(' ').first;
}

/// The supervisor's "Price requests" card: waiting ones (oldest first), and
/// those answered or ended by closing the category in the last
/// [shownFor] (newest first). Withdrawn by the supervisor: not shown.
final class SupervisorPriceRequests {
  const SupervisorPriceRequests({required this.waiting, required this.recent});

  final List<PriceRequestView> waiting;
  final List<PriceRequestView> recent;

  static const shownFor = Duration(days: 14);

  /// The waiting request for [categoryId], if any.
  PriceRequestView? waitingFor(String categoryId) {
    for (final v in waiting) {
      if (v.request.categoryId == categoryId) return v;
    }
    return null;
  }
}

/// Price requests (BR-2): the supervisor asks and withdraws, the owner
/// decides; an approval changes the price in the same transaction. The rules
/// are in `domain/price_request.dart`; every write re-checks them inside its
/// transaction, and the database's triggers check them again.
class PriceRequestsRepository {
  PriceRequestsRepository(this._db, this._audit, {this._cloud});

  final AppDatabase _db;
  final AuditWriter _audit;

  /// Once this desk is connected, decisions and withdrawals go to the
  /// cloud first.
  final CloudWrites? _cloud;

  /// Fires when a request, decision or price changes.
  Stream<void> changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.priceRequests,
          _db.priceDecisions,
          _db.bedCategories,
        ]),
      )
      .map((_) {});

  // ── Reading ────────────────────────────────────────────────────────────

  Future<PriceRequestView> view(String requestId) async =>
      (await _views(where: _db.priceRequests.id.equals(requestId))).single;

  /// Requests waiting for the owner, oldest first.
  Future<List<PriceRequestView>> waiting() async => [
    for (final v in (await _views()).reversed)
      if (v.status == PriceRequestStatus.waiting) v,
  ];

  /// The supervisor's card at [now].
  Future<SupervisorPriceRequests> forSupervisor(DateTime now) async {
    final all = await _views();
    final since = now.subtract(SupervisorPriceRequests.shownFor);
    return SupervisorPriceRequests(
      waiting: [
        for (final v in all.reversed)
          if (v.status == PriceRequestStatus.waiting) v,
      ],
      recent: [
        for (final v in all)
          if (_endedAt(v.request) case final at?
              when at.isAfter(since) &&
                  (v.status != PriceRequestStatus.withdrawn ||
                      v.request.withdrawal!.categoryClosed))
            v,
      ],
    );
  }

  static DateTime? _endedAt(PriceRequest r) =>
      r.decision?.decidedAt ?? r.withdrawal?.at;

  /// Newest first.
  Future<List<PriceRequestView>> _views({Expression<bool>? where}) async {
    final requester = _db.alias(_db.users, 'requester');
    final decider = _db.alias(_db.users, 'decider');
    final query = _db.select(_db.priceRequests).join([
      innerJoin(
        _db.bedCategories,
        _db.bedCategories.id.equalsExp(_db.priceRequests.categoryId),
      ),
      innerJoin(
        requester,
        requester.id.equalsExp(_db.priceRequests.requestedBy),
      ),
      leftOuterJoin(
        _db.priceDecisions,
        _db.priceDecisions.requestId.equalsExp(_db.priceRequests.id),
      ),
      leftOuterJoin(
        decider,
        decider.id.equalsExp(_db.priceDecisions.decidedBy),
      ),
    ]);
    if (where != null) query.where(where);
    query.orderBy([OrderingTerm.desc(_db.priceRequests.requestedAt)]);
    return [
      for (final row in await query.get())
        PriceRequestView(
          request: toRequest(
            row.readTable(_db.priceRequests),
            row.readTableOrNull(_db.priceDecisions),
          ),
          categoryName: row.readTable(_db.bedCategories).name,
          currentPrice: row.readTable(_db.bedCategories).pricePerNight,
          requestedByName: row.readTable(requester).fullName,
          requestedByRole: Role.parse(row.readTable(requester).role),
          decidedByName: row.readTableOrNull(decider)?.fullName,
        ),
    ];
  }

  /// The domain request for a `price_requests` row and its decision, if any.
  static PriceRequest toRequest(PriceRequestRow r, PriceDecisionRow? d) =>
      PriceRequest(
        id: r.id,
        categoryId: r.categoryId,
        oldPrice: r.oldPrice,
        newPrice: r.newPrice,
        reason: r.reason,
        requestedBy: r.requestedBy,
        requestedAt: r.requestedAt,
        decision: d == null
            ? null
            : PriceDecision(
                kind: PriceDecisionKind.parse(d.decision),
                note: d.note,
                decidedBy: d.decidedBy,
                decidedAt: d.decidedAt,
              ),
        withdrawal: r.withdrawnAt == null
            ? null
            : PriceWithdrawal(
                by: r.withdrawnBy!,
                at: r.withdrawnAt!,
                reason: r.withdrawReason,
              ),
      );

  static Future<PriceRequest> _request(AppDatabase db, String id) async {
    final r = await (db.select(
      db.priceRequests,
    )..where((x) => x.id.equals(id))).getSingle();
    final d = await (db.select(
      db.priceDecisions,
    )..where((x) => x.requestId.equals(id))).getSingleOrNull();
    return toRequest(r, d);
  }

  /// [categoryId]'s waiting request, if any.
  static Future<PriceRequest?> _waitingFor(
    AppDatabase db,
    String categoryId,
  ) async {
    final decided = db.selectOnly(db.priceDecisions)
      ..addColumns([db.priceDecisions.requestId]);
    final row =
        await (db.select(db.priceRequests)..where(
              (r) =>
                  r.categoryId.equals(categoryId) &
                  r.withdrawnAt.isNull() &
                  r.id.isNotInQuery(decided),
            ))
            .getSingleOrNull();
    return row == null ? null : toRequest(row, null);
  }

  static Future<BedCategory> _category(AppDatabase db, String id) async {
    final r = await (db.select(
      db.bedCategories,
    )..where((c) => c.id.equals(id))).getSingle();
    return BedCategory(
      id: r.id,
      name: r.name,
      pricePerNight: r.pricePerNight,
      sortOrder: r.sortOrder,
      isActive: r.isActive,
    );
  }

  // ── Asking (the supervisor) ────────────────────────────────────────────

  /// Asks the owner for [newPrice] on [categoryId] (`price.request`), against
  /// its price now. Returns the request's id. Throws [NotPermitted],
  /// [InvalidRequestedPrice] or [PriceRequestRuleViolation].
  Future<String> request(
    UserAccount user, {
    required String categoryId,
    required int? newPrice,
    String? reason,
  }) async {
    requirePermission(user, Permission.requestPriceChange);
    try {
      return await _audit.writeWithAudit(
        action: 'price.request',
        userId: user.id,
        body: (w) async {
          final asked = requestPriceChange(
            await _category(_db, categoryId),
            id: w.newId(),
            newPrice: newPrice,
            reason: reason,
            by: user,
            at: w.now,
            open: await _waitingFor(_db, categoryId),
          );
          await w.insert(
            _db.priceRequests,
            PriceRequestsCompanion.insert(
              id: Value(asked.id),
              categoryId: asked.categoryId,
              oldPrice: asked.oldPrice,
              newPrice: asked.newPrice,
              reason: Value(asked.reason),
              requestedBy: asked.requestedBy,
              requestedAt: asked.requestedAt,
            ),
          );
          return asked.id;
        },
      );
    } on PriceRequestRuleViolation {
      rethrow;
    } on InvalidRequestedPrice {
      rethrow;
    } on NotPermitted {
      rethrow;
    } catch (e) {
      if ('$e'.contains('open price request')) {
        throw const PriceRequestRuleViolation(
          'This category already has a request waiting for the owner.',
        );
      }
      rethrow;
    }
  }

  /// Withdraws the user's own waiting request (`price.request_withdraw`);
  /// once connected, in the cloud first (the owner's decision may win).
  /// Throws [NotPermitted] or [PriceRequestRuleViolation].
  Future<void> withdraw(UserAccount user, String requestId) async {
    requirePermission(user, Permission.requestPriceChange);
    final at = _audit.now();
    final cloud = _cloud;
    final inCloud = cloud != null && cloud.active;
    if (inCloud) {
      withdrawPriceRequest(await _request(_db, requestId), by: user, at: at);
      await _cloudWithdraw(
        cloud,
        requestId: requestId,
        by: user.id,
        reason: null,
        at: at,
        needsInternet: 'Withdrawing a request needs an internet connection.',
      );
    }
    try {
      await _audit.writeWithAudit(
        action: 'price.request_withdraw',
        userId: user.id,
        inCloud: {if (inCloud) 'price_requests'},
        body: (w) async {
          final done = withdrawPriceRequest(
            await _request(_db, requestId),
            by: user,
            at: at,
          );
          await _writeWithdrawal(w, _db, done);
        },
      );
    } on PriceRequestRuleViolation {
      rethrow;
    } on NotPermitted {
      rethrow;
    } catch (e) {
      // The owner's decision got in first.
      if ('$e'.contains('already decided')) {
        throw const PriceRequestRuleViolation(
          'The owner has already decided this request.',
        );
      }
      rethrow;
    }
  }

  /// Before the owner closes [categoryId], once connected: its waiting
  /// request, if any, is withdrawn in the cloud first, at [at] (the owner's
  /// decision may have won). Returns whether there was one. Throws
  /// [CategoryRuleViolation] with the reason.
  static Future<bool> withdrawInCloudBeforeClose(
    AppDatabase db,
    CloudWrites cloud,
    UserAccount owner,
    String categoryId,
    DateTime at,
  ) async {
    final open = await _waitingFor(db, categoryId);
    if (open == null) return false;
    final name = (await _category(db, categoryId)).name;
    withdrawForClosedCategory(open, by: owner, at: at);
    try {
      await _cloudWithdraw(
        cloud,
        requestId: open.id,
        by: owner.id,
        reason: categoryClosedReason,
        at: at,
        needsInternet:
            'Closing $name withdraws its price request, which needs an '
            'internet connection.',
      );
    } on PriceRequestRuleViolation catch (e) {
      throw CategoryRuleViolation(e.message);
    }
    return true;
  }

  static Future<void> _cloudWithdraw(
    CloudWrites cloud, {
    required String requestId,
    required String by,
    required String? reason,
    required DateTime at,
    required String needsInternet,
  }) async {
    try {
      await cloud.withdrawPriceRequest(
        requestId: requestId,
        by: by,
        reason: reason,
        at: at,
      );
    } on CloudWriteRefused catch (e) {
      throw PriceRequestRuleViolation(switch (e) {
        DecidedElsewhere() => 'The owner has already decided this request.',
        _ => cloudRefusalMessage(e, needsInternet: needsInternet),
      });
    }
  }

  /// Inside the owner's closing of [categoryId] (`category.update`): its
  /// waiting request, if any, is withdrawn too, "Category closed", by
  /// [owner] (`price.request_withdraw`, same operation), at [at] when the
  /// cloud has it already.
  static Future<void> withdrawOnClose(
    AuditedWrites w,
    AppDatabase db,
    UserAccount owner,
    String categoryId, {
    DateTime? at,
  }) async {
    final open = await _waitingFor(db, categoryId);
    if (open == null) return;
    await _writeWithdrawal(
      w,
      db,
      withdrawForClosedCategory(open, by: owner, at: at ?? w.now),
      action: 'price.request_withdraw',
    );
  }

  static Future<void> _writeWithdrawal(
    AuditedWrites w,
    AppDatabase db,
    PriceRequest done, {
    String? action,
  }) async {
    final withdrawal = done.withdrawal!;
    await w.update(
      db.priceRequests,
      done.id,
      PriceRequestsCompanion(
        withdrawnAt: Value(withdrawal.at),
        withdrawnBy: Value(withdrawal.by),
        withdrawReason: Value(withdrawal.reason),
      ),
      action: action,
    );
  }

  // ── Deciding (the owner) ───────────────────────────────────────────────

  /// Approves (`price.approve`, and the new price as `price.update` in the
  /// same operation) or, with a [note], rejects (`price.reject`)
  /// [requestId]: once; never one the price has moved on from. Throws
  /// [NotPermitted], [StalePriceRequest] or [PriceRequestRuleViolation].
  ///
  /// Once this desk is connected the decision (and the new price) is
  /// written in the cloud first, then here with the same id and time.
  /// Throws [OwnerCloudSignInNeeded] when the owner's cloud sign-in is
  /// missing.
  Future<void> decide(
    UserAccount owner,
    String requestId, {
    required bool approve,
    String? note,
  }) async {
    requirePermission(owner, Permission.decidePriceChange);
    final id = const Uuid().v4();
    final at = _audit.now();
    Future<PriceRequest> decided() async {
      final current = await _request(_db, requestId);
      return approve
          ? approvePriceRequest(
              current,
              category: await _category(_db, current.categoryId),
              by: owner,
              at: at,
            )
          : rejectPriceRequest(current, by: owner, note: note, at: at);
    }

    final cloud = _cloud;
    final inCloud = cloud != null && cloud.active;
    if (inCloud) {
      final decision = (await decided()).decision!;
      try {
        await cloud.decidePriceRequest(
          id: id,
          requestId: requestId,
          approve: approve,
          note: decision.note,
          at: at,
        );
      } on OwnerCloudSignInNeeded {
        rethrow;
      } on StaleElsewhere catch (e) {
        final current = await _request(_db, requestId);
        final category = await _category(_db, current.categoryId);
        throw StalePriceRequest(
          staleError(
            current,
            BedCategory(
              id: category.id,
              name: category.name,
              pricePerNight: e.currentPrice,
              sortOrder: category.sortOrder,
              isActive: category.isActive,
            ),
          )!,
        );
      } on CloudWriteRefused catch (e) {
        throw PriceRequestRuleViolation(
          cloudRefusalMessage(
            e,
            needsInternet: approve
                ? 'Approving needs an internet connection.'
                : 'Rejecting needs an internet connection.',
          ),
        );
      }
    }
    try {
      await _audit.writeWithAudit(
        action: approve ? 'price.approve' : 'price.reject',
        userId: owner.id,
        inCloud: {
          if (inCloud) ...{'price_decisions', 'bed_categories'},
        },
        body: (w) async {
          final decision = await decided();
          final row = decision.decision!;
          await w.insert(
            _db.priceDecisions,
            PriceDecisionsCompanion.insert(
              id: Value(id),
              requestId: requestId,
              decision: row.kind.code,
              note: Value(row.note),
              decidedBy: owner.id,
              decidedAt: row.decidedAt,
            ),
          );
          if (approve) {
            // BR-3: new check-ins only; stays keep their charges' price.
            await w.update(
              _db.bedCategories,
              decision.categoryId,
              BedCategoriesCompanion(pricePerNight: Value(decision.newPrice)),
              action: 'price.update',
            );
          }
        },
      );
    } on PriceRequestRuleViolation {
      rethrow;
    } on StalePriceRequest {
      rethrow;
    } on NotPermitted {
      rethrow;
    } catch (e) {
      // Another decision got in first (price_decisions.request_id is
      // UNIQUE): the first one wins.
      if ('$e'.contains('UNIQUE')) {
        throw const PriceRequestRuleViolation(
          'This request has already been decided.',
        );
      }
      if ('$e'.contains('was withdrawn')) {
        throw const PriceRequestRuleViolation('This request was withdrawn.');
      }
      rethrow;
    }
  }
}
