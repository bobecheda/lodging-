import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/housekeeping/data/housekeeping_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/data/staff_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount desk;
  late RoomsRepository rooms;
  late StaffRepository staff;
  late RoomSummary r7;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    supervisor = await env.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('desk');
    rooms = RoomsRepository(env.db, env.audit);
    staff = StaffRepository(env.db, env.audit, env.hasher);
    r7 = await rooms.createRoom(
      supervisor,
      const NewRoom(
        number: '7',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: SeedIds.comfort,
      ),
    );
    // Bed A: one night, checked out Fri 09:30, so it needs cleaning.
    final stay = await env.checkIn(r7.beds.first.id, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 9, 30));
    await env.checkOut(stay, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 11, 40));
  });
  tearDown(() => env.close());

  Future<void> housekeepers() async {
    await staff.addHousekeeper(supervisor, name: 'Rose Akinyi', phone: '');
    await staff.addHousekeeper(supervisor, name: 'Jane Wanjiru', phone: '');
  }

  Future<void> onBoard(WidgetTester tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
  }

  Finder tileText(String text) => find.descendant(
    of: find.byKey(const ValueKey('board.bed.7A')),
    matching: find.text(text),
  );

  Future<void> choose(WidgetTester tester, String name) async {
    await tapKey(tester, 'cleaning.housekeeper');
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('assign, then mark clean: TO CLEAN → READY; the tile line and '
      'the room badge follow', (tester) async {
    await housekeepers();
    await onBoard(tester);
    expect(tileText('Needs cleaning · assign'), findsOneWidget);
    expect(find.byKey(const ValueKey('board.room.7.toClean')), findsOneWidget);

    await tapKey(tester, 'board.bed.7A');
    expect(text(tester, 'cleaning.title'), 'Room 7 · Bed A');
    expect(find.text('Last checkout Fri 16 Oct, 09:30.'), findsOneWidget);
    await choose(tester, 'Rose');
    await tapKey(tester, 'cleaning.assign');
    expect(text(tester, 'cleaning.assignee'), 'Rose · assigned 11:40');

    await tapKey(tester, 'cleaning.closeIcon');
    expect(tileText('Needs cleaning · Rose'), findsOneWidget);

    await tapKey(tester, 'board.bed.7A');
    await tapKey(tester, 'cleaning.markClean');
    expect(find.byKey(const ValueKey('cleaning.done')), findsOneWidget);
    await tapKey(tester, 'cleaning.close');
    expect(tileText('READY'), findsOneWidget);
    expect(find.byKey(const ValueKey('board.room.7.toClean')), findsNothing);
  });

  testWidgets('already cleaned: one step', (tester) async {
    await housekeepers();
    await onBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await choose(tester, 'Jane');
    await tapKey(tester, 'cleaning.cleanNow');
    expect(find.byKey(const ValueKey('cleaning.done')), findsOneWidget);
    final task = await env.db.select(env.db.housekeepingTasks).getSingle();
    expect(task.completedAt, isNotNull);
  });

  testWidgets('reassign to someone else', (tester) async {
    await housekeepers();
    await onBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    await choose(tester, 'Rose');
    await tapKey(tester, 'cleaning.assign');
    await tapKey(tester, 'cleaning.reassign');
    await choose(tester, 'Jane');
    await tapKey(tester, 'cleaning.reassignSave');
    expect(text(tester, 'cleaning.assignee'), 'Jane · assigned 11:40');
  });

  testWidgets('no housekeepers yet: says where the supervisor adds them', (
    tester,
  ) async {
    await onBoard(tester);
    await tapKey(tester, 'board.bed.7A');
    expect(
      find.byKey(const ValueKey('cleaning.noHousekeepers')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('cleaning.assign')), findsNothing);
  });

  testWidgets('closing the bed cancels its cleaning; reopened, it needs '
      'assigning again', (tester) async {
    await housekeepers();
    final rose = (await env.db.select(env.db.housekeepers).get()).firstWhere(
      (h) => h.fullName == 'Rose Akinyi',
    );
    final repo = HousekeepingRepository(env.db, env.audit);
    await repo.assign(desk, r7.beds.first.id, rose.id);
    await rooms.deactivateBed(supervisor, r7.beds.first.id);
    await rooms.reactivateBed(supervisor, r7.beds.first.id);

    await onBoard(tester);
    expect(tileText('Needs cleaning · assign'), findsOneWidget);
    final task = await env.db.select(env.db.housekeepingTasks).getSingle();
    expect(task.cancelledAt, isNotNull);
    expect(task.completedAt, isNull);
  });
}
