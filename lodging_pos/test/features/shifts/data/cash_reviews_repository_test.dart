import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/desk_secret_store.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/cash_reviews_repository.dart';
import 'package:lodging_pos/features/shifts/data/drawer_repository.dart';
import 'package:lodging_pos/features/shifts/domain/cash_review.dart';
import 'package:lodging_pos/features/shifts/domain/drawer.dart';

import '../../../helpers/fake_cloud.dart';
import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late UserAccount mary;
  late CashReviewsRepository reviews;
  late String maryShift;
  late RoomSummary room;

  /// Mary's shift: starting cash 2,000, KES 700 cash, closed counting
  /// 2,600 twice: needs review.
  Future<String> maryClosesShort() async {
    final id = (await env.openShift(mary, startingCash: 2000)).id;
    env.clock.set(nairobiInstant(2026, 11, 16, 9));
    await env.checkIn(room.beds.first.id, by: mary);
    env.clock.set(nairobiInstant(2026, 11, 16, 20));
    await env.closeShiftWith(
      mary,
      id,
      firstCount: 2600,
      reason: 'Gave change from my pocket',
    );
    return id;
  }

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 11, 16, 8));
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    mary = await env.addReceptionist('mary');
    room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '4',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: SeedIds.comfort,
      ),
    );
    maryShift = await maryClosesShort();
    reviews = CashReviewsRepository(env.db, env.audit);
  });
  tearDown(() => env.close());

  Future<CashReviewRow?> reviewOf(String id) => (env.db.select(
    env.db.cashReviews,
  )..where((r) => r.targetId.equals(id))).getSingleOrNull();

  group('on the desk, not connected (everything local)', () {
    test('the supervisor approves Mary’s close: one row, audited '
        'shift.review_approve, the chain shows it', () async {
      expect(
        await reviews.statusOf(ReviewTargetKind.shift, maryShift),
        ReviewStatus.awaiting,
      );
      await reviews.decide(
        supervisor,
        ReviewTargetKind.shift,
        maryShift,
        approve: true,
      );
      final r = (await reviewOf(maryShift))!;
      expect(
        (r.decision, r.decidedBy, r.reason),
        ('approved', supervisor.id, null),
      );
      expect(
        (await env.auditFor('shift.review_approve')).single.userId,
        supervisor.id,
      );
      expect(
        await reviews.statusOf(ReviewTargetKind.shift, maryShift),
        ReviewStatus.approved,
      );
    });

    test('decided once', () async {
      await reviews.decide(
        supervisor,
        ReviewTargetKind.shift,
        maryShift,
        approve: true,
      );
      await expectLater(
        reviews.decide(
          owner,
          ReviewTargetKind.shift,
          maryShift,
          approve: false,
          reason: 'No',
        ),
        throwsA(isA<CashReviewProblem>()),
      );
    });

    test(
      'a rejection needs a reason; it is the owner’s attention row',
      () async {
        await expectLater(
          reviews.decide(
            supervisor,
            ReviewTargetKind.shift,
            maryShift,
            approve: false,
          ),
          throwsA(isA<CashReviewProblem>()),
        );
        env.clock.set(nairobiInstant(2026, 11, 17, 9));
        await reviews.decide(
          supervisor,
          ReviewTargetKind.shift,
          maryShift,
          approve: false,
          reason: 'The reason doesn’t explain KES 100',
        );
        expect(await env.auditFor('shift.review_reject'), hasLength(1));
        final rows = await reviews.rejectedSince(
          nairobiInstant(2026, 11, 10, 0),
          by: owner,
        );
        expect(rows.single.title, 'Cash review rejected');
        expect(
          rows.single.subtitle,
          'Desk MARY’s shift close · by Grace Supervisor: The reason doesn’t '
          'explain KES 100',
        );
        expect(rows.single.figure, 'KES 100 short');
      },
    );

    test('bypass: a receptionist never decides', () async {
      await expectLater(
        reviews.decide(mary, ReviewTargetKind.shift, maryShift, approve: true),
        throwsA(isA<NotPermitted>()),
      );
      expect(await reviewOf(maryShift), isNull);
    });

    test('bypass: nobody decides their own shift; a supervisor’s shift is '
        'the owner’s', () async {
      // The supervisor closes a shift of their own, short.
      final own = (await env.openShift(supervisor)).id;
      await env.closeShiftWith(supervisor, own, firstCount: 0, reason: 'x');
      await expectLater(
        reviews.decide(supervisor, ReviewTargetKind.shift, own, approve: true),
        throwsA(isA<CashReviewProblem>()),
      );
      final otto = await env.addSupervisor('otto');
      await expectLater(
        reviews.decide(otto, ReviewTargetKind.shift, own, approve: true),
        throwsA(
          isA<CashReviewProblem>().having(
            (e) => e.message,
            'message',
            'A supervisor is named in this: the owner decides.',
          ),
        ),
      );
      await reviews.decide(owner, ReviewTargetKind.shift, own, approve: true);
    });

    test(
      'bypass: a close made by the supervisor for Mary is the owner’s',
      () async {
        final id = (await env.openShift(mary)).id;
        await env.closeShiftWith(supervisor, id, firstCount: 0, reason: 'x');
        await expectLater(
          reviews.decide(supervisor, ReviewTargetKind.shift, id, approve: true),
          throwsA(isA<CashReviewProblem>()),
        );
      },
    );

    test('bypass: the owner’s own count is the owner’s; a supervisor’s '
        'count is the owner’s', () async {
      final drawer = DrawerRepository(env.db, env.audit, env.hasher, env.clock);
      await env.openShift(mary);
      env.clock.set(nairobiInstant(2026, 11, 17, 12));
      // Each counts short of what the drawer should hold, twice.
      Future<String> countBy(UserAccount by, int count) async =>
          (await drawer.recordCount(
            by,
            await drawer.cosign(
              by,
              presentUserId: mary.id,
              password: 'desk-pass',
            ),
            kind: DrawerCountKind.check,
            firstCount: count,
            recount: count,
            note: 'Short',
          )).id;
      final byOwner = await countBy(owner, 1);
      env.clock.set(nairobiInstant(2026, 11, 17, 13));
      final bySupervisor = await countBy(supervisor, 0);
      for (final id in [byOwner, bySupervisor]) {
        await expectLater(
          reviews.decide(
            supervisor,
            ReviewTargetKind.drawerEvent,
            id,
            approve: true,
          ),
          throwsA(isA<CashReviewProblem>()),
          reason: id,
        );
      }
      await reviews.decide(
        owner,
        ReviewTargetKind.drawerEvent,
        byOwner,
        approve: false,
        reason: 'I miscounted? No: the drawer was short',
      );
      expect(
        (await env.auditFor('drawer.review_reject')).single.userId,
        owner.id,
      );
    });

    test('nothing to review: a close that matched', () async {
      final id = (await env.openShift(mary)).id;
      await env.closeShiftWith(mary, id, firstCount: 2600);
      await expectLater(
        reviews.decide(supervisor, ReviewTargetKind.shift, id, approve: true),
        throwsA(isA<CashReviewProblem>()),
      );
    });

    test('only viewShiftTotals users read the reviews', () async {
      await expectLater(
        reviews.rejectedSince(DateTime.utc(2026), by: mary),
        throwsA(isA<NotPermitted>()),
      );
      expect(can(mary, Permission.reviewCash), isFalse);
    });
  });

  group('connected: the cloud first', () {
    late FakeCloud cloud;
    late SyncEngine engine;

    setUp(() async {
      cloud = FakeCloud(serverNow: () => env.clock.now());
      engine = SyncEngine(
        db: env.db,
        audit: env.audit,
        cloud: cloud,
        secrets: MemoryDeskSecretStore(),
        clock: env.clock,
      );
      await engine.start();
      await engine.connect(
        owner: owner,
        installCode: 'ABCD-EFGH-JKLM',
        ownerEmail: testOwnerEmail,
        password: testOwner.password,
      );
      reviews = CashReviewsRepository(env.db, env.audit, cloud: engine);
    });
    tearDown(() => engine.dispose());

    test('the supervisor’s decision goes up through the desk’s sign-in, in '
        'their name, then here, its outbox row already sent', () async {
      await reviews.decide(
        supervisor,
        ReviewTargetKind.shift,
        maryShift,
        approve: true,
      );
      final local = (await reviewOf(maryShift))!;
      final there = cloud.row('cash_reviews', local.id)!;
      expect(
        (there['decided_by'], there['decision']),
        (supervisor.id, 'approved'),
      );
      final outbox = await (env.db.select(
        env.db.outbox,
      )..where((o) => o.targetRowId.equals(local.id))).getSingle();
      expect(outbox.sentAt, isNotNull);
    });

    test('offline: nothing is decided, and it says so', () async {
      cloud.offline = true;
      await expectLater(
        reviews.decide(
          supervisor,
          ReviewTargetKind.shift,
          maryShift,
          approve: true,
        ),
        throwsA(
          isA<CashReviewProblem>().having(
            (e) => e.message,
            'message',
            'Deciding needs an internet connection.',
          ),
        ),
      );
      expect(await reviewOf(maryShift), isNull);
    });

    test('decided elsewhere first (the owner on the phone): refused here, '
        'and the pull brings that decision', () async {
      await engine.pushNow();
      await cloud.decideCashReview(
        id: 'r-phone',
        targetType: 'shift',
        targetId: maryShift,
        decision: 'rejected',
        reason: 'Talk to me',
        decidedBy: owner.id,
        asOwner: true,
        at: env.clock.now(),
        deviceId: 'phone-1',
      );
      await expectLater(
        reviews.decide(
          supervisor,
          ReviewTargetKind.shift,
          maryShift,
          approve: true,
        ),
        throwsA(
          isA<CashReviewProblem>().having(
            (e) => e.message,
            'message',
            startsWith('Already decided by Amina Owner'),
          ),
        ),
      );
      await engine.pullNow();
      final pulled = (await reviewOf(maryShift))!;
      expect((pulled.id, pulled.decision), ('r-phone', 'rejected'));
      expect(
        await reviews.statusOf(ReviewTargetKind.shift, maryShift),
        ReviewStatus.rejected,
      );
    });
  });
}
