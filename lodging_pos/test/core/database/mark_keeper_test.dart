import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/mark_keeper.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/recording_marks.dart';

/// The mark moves with the work (story/desk-db-guards-2): after every
/// receipt number, shift open or close and drawer count, once the
/// transaction has committed, both copies are raised to the live figures.
void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late RecordingMarks marks;

  setUp(() async {
    env = TestEnv();
    supervisor = await env.createFirstSupervisor(testSetup);
    marks = RecordingMarks();
    env.audit.onCommitted = MarkKeeper(env.db, marks, env.clock).afterCommit;
  });
  tearDown(() => env.close());

  Future<String> bed(String number) async =>
      (await RoomsRepository(env.db, env.audit).createRoom(
        supervisor,
        NewRoom(
          number: number,
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      )).beds.single.id;

  test('the starting cash, a shift opened, a payment and a shift closed each '
      'raise it to the live figures', () async {
    final bedId = await bed('5');
    expect(marks.raised, isEmpty, reason: 'setting up rooms moves nothing');

    await env.startDrawer(counted: 1000, by: supervisor);
    expect(marks.raised, hasLength(1));

    final shift = await env.openShift(supervisor);
    expect(marks.raised, hasLength(2));

    await env.checkIn(bedId, by: supervisor);
    final afterPayment = marks.raised.last.figures;
    expect(marks.raised, hasLength(3));
    expect(afterPayment.payments, 1);
    expect(afterPayment.stays, 1);
    expect(afterPayment.lastReceipt, 'R-000001');
    expect(afterPayment.lastAuditAt, isNotNull);
    expect(marks.raised.last.at, env.clock.now());
    expect(marks.raised.last.backupName, isNull);

    await env.closeShiftWith(supervisor, shift.id, firstCount: 1700);
    expect(marks.raised.length, greaterThanOrEqualTo(4));
  });

  test('other work leaves it alone', () async {
    await bed('6');
    await env.audit.recordEvent(
      action: 'user.login',
      userId: supervisor.id,
      entity: 'users',
      entityId: supervisor.id,
    );
    expect(marks.raised, isEmpty);
  });

  test('liveFigures reads the open database as the startup check reads the '
      'file', () async {
    final f = await liveFigures(env.db);
    expect(f.schemaVersion, env.db.schemaVersion);
    expect(f.payments, 0);
    expect(f.auditEntries, greaterThan(0));
  });
}
