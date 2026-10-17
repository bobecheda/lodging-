import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/bed_board/data/bed_board_repository.dart';
import 'package:lodging_pos/features/bed_board/domain/bed_board.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/prices_settings.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late BedBoardRepository board;
  late RoomsRepository rooms;
  late UserAccount owner;

  setUp(() async {
    env = TestEnv();
    board = BedBoardRepository(env.db);
    rooms = RoomsRepository(env.db, env.audit);
    owner = await env.users.createFirstAdmin(testSetup);
  });
  tearDown(() => env.close());

  Future<RoomSummary> room(String number, {bool twoBeds = true}) =>
      rooms.createRoom(
        owner,
        NewRoom(
          number: number,
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: twoBeds ? SeedIds.normal : null,
        ),
      );

  test('open rooms with their active beds, categories and stays', () async {
    final three = await room('3');
    await room('4', twoBeds: false);
    final closed = await room('9');
    await rooms.deactivateRoom(owner, closed.id);
    await rooms.deactivateBed(owner, three.beds.last.id);
    await env.checkIn(three.beds.first.id, by: owner, nights: 2);

    final list = await board.watchBoard().first;
    expect({for (final r in list) r.number}, {'3', '4'});
    final r3 = list.firstWhere((r) => r.number == '3');
    expect(r3.beds, hasLength(1)); // bed B is closed
    final a = r3.beds.single;
    expect((a.categoryName, a.pricePerNight), ('Deluxe', 700));
    expect(a.stay!.guestName, 'Test Guest');
    expect(a.stay!.guestPhone, '0700000000');
  });

  test('the board stream updates after a check-in and a checkout', () async {
    final four = await room('4', twoBeds: false);
    final emissions = <List<BoardRoom>>[];
    final sub = board.watchBoard().listen(emissions.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emissions.last.single.beds.single.stay, isNull);

    final stayId = await env.checkIn(four.beds.single.id, by: owner);
    await pumpEventQueue();
    expect(emissions.last.single.beds.single.stay, isNotNull);

    await env.checkOut(stayId, by: owner);
    await pumpEventQueue();
    final bed = emissions.last.single.beds.single;
    expect(bed.stay, isNull);
  });

  test('grace minutes follow the setting', () async {
    final values = <int>[];
    final sub = board.watchGraceMinutes().listen(values.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(values.last, 60);

    final prices = PricesRepository(env.db, env.audit);
    final s = await prices.settings();
    await prices.saveSettings(
      owner,
      SettingsInput(
        lodgingName: s.lodgingName,
        checkoutTime: const ClockTime(10, 0),
        graceMinutes: '30',
        idleLockMinutes: s.idleLockMinutes,
        receiptPrefix: s.receiptPrefix,
      ),
    );
    await pumpEventQueue();
    expect(values.last, 30);
  });
}
