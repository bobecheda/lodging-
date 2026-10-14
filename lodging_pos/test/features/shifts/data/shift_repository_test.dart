import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late ShiftRepository shifts;

  setUp(() {
    env = TestEnv();
    shifts = ShiftRepository(env.db, env.audit);
  });
  tearDown(() => env.close());

  test('no shift is open on a fresh device', () async {
    expect(await shifts.openShiftOnThisDevice(), isNull);
  });

  test('opening a shift records the float and audits shift.open', () async {
    final desk = await env.addReceptionist('desk');
    final opened = await shifts.openShift(user: desk, openingFloat: 1500);
    expect(opened.openingFloat, 1500);
    expect(opened.openedAt, env.clock.now());
    expect(opened.userName, desk.fullName);

    final current = (await shifts.openShiftOnThisDevice())!;
    expect(current.id, opened.id);
    expect(current.userId, desk.id);
    expect(current.userName, desk.fullName);

    final entry = (await env.auditFor('shift.open')).single;
    expect(entry.userId, desk.id);
    expect(jsonDecode(entry.afterJson)['opening_float'], 1500);
  });

  test('a zero float is allowed', () async {
    final desk = await env.addReceptionist('desk');
    expect(
      (await shifts.openShift(user: desk, openingFloat: 0)).openingFloat,
      0,
    );
  });

  test('a negative float is rejected without writing', () async {
    final desk = await env.addReceptionist('desk');
    await expectLater(
      shifts.openShift(user: desk, openingFloat: -1),
      throwsArgumentError,
    );
    expect(await shifts.openShiftOnThisDevice(), isNull);
  });

  test('only one shift can be open on a device', () async {
    final desk = await env.addReceptionist('desk');
    final tom = await env.addReceptionist('tom');
    await shifts.openShift(user: desk, openingFloat: 1000);
    await expectLater(
      shifts.openShift(user: tom, openingFloat: 500),
      throwsA(
        isA<ShiftAlreadyOpen>().having((e) => e.shift.userId, 'owner', desk.id),
      ),
    );
    expect(await env.auditFor('shift.open'), hasLength(1));
  });
}
