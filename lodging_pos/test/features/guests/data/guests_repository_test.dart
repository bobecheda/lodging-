import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/guests/data/guests_repository.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late GuestsRepository guests;
  late UserAccount desk;

  setUp(() async {
    env = TestEnv();
    guests = GuestsRepository(env.db, env.audit);
    await env.users.createFirstAdmin(testSetup);
    desk = await env.addReceptionist('desk');
  });
  tearDown(() => env.close());

  Future<Guest> grace({
    String phone = '0722 418 905',
    IdType? idType = IdType.nationalId,
    String idNumber = '12343921',
  }) => guests.register(
    desk,
    GuestForm(
      fullName: ' Grace  Achieng ',
      phone: phone,
      idType: idType,
      idNumber: idNumber,
    ),
  );

  Future<List<String>> names(String query) async => [
    for (final g in await guests.search(GuestQuery.parse(query))) g.fullName,
  ];

  Matcher fieldError(GuestField field, String message) => throwsA(
    isA<InvalidGuest>().having((e) => e.errors, 'errors', {field: message}),
  );

  test(
    'a receptionist registers a guest (guest.create), stored normalized',
    () async {
      final g = await grace(phone: '+254 722 418 905');
      expect(
        (g.fullName, g.phone, g.idType, g.idNumber),
        ('Grace Achieng', '0722418905', IdType.nationalId, '12343921'),
      );
      expect(g.maskedId, 'National ID ••••3921');

      final entry = (await env.auditFor('guest.create')).single;
      final after = jsonDecode(entry.afterJson) as Map;
      expect(after['full_name'], '[redacted]');
      expect(after['phone'], '0722•••905');
      expect(after['id_number'], '••••3921');
      expect(entry.userId, desk.id);
    },
  );

  test('finds guests by phone or ID prefix as you type', () async {
    await grace();
    await guests.register(
      desk,
      const GuestForm(
        fullName: 'Peter Okello',
        phone: '+256 712 345 678',
        idType: IdType.passport,
        idNumber: 'b1234567',
      ),
    );
    expect(await names('0722 41'), ['Grace Achieng']);
    expect(await names('+254 722'), ['Grace Achieng']);
    expect(await names('1234'), ['Grace Achieng']); // ID prefix
    expect(await names('b123'), ['Peter Okello']); // any case
    expect(await names('+2567'), ['Peter Okello']);
    expect(await names('07'), isEmpty); // too short
    expect(await names('Grace'), isEmpty); // names aren't searched
  });

  test('at most 8 matches, by name', () async {
    for (var i = 0; i < 10; i++) {
      await guests.register(
        desk,
        GuestForm(
          fullName: 'Guest $i',
          phone: '07220000${i.toString().padLeft(2, '0')}',
          idType: null,
          idNumber: '',
        ),
      );
    }
    final found = await names('0722');
    expect(found, hasLength(8));
    expect(found.first, 'Guest 0');
  });

  test('the same ID (type + number) cannot be registered twice', () async {
    await grace();
    await expectLater(
      grace(phone: '0711 000 111', idNumber: '1234 3921'),
      fieldError(
        GuestField.idNumber,
        'This ID is already registered to another guest.',
      ),
    );
    // The same digits as another type are a different document.
    final other = await grace(idType: IdType.alienId, idNumber: '12343921');
    expect(other.idType, IdType.alienId);
  });

  test('a shared phone is allowed; others with it are listed', () async {
    final first = await grace(idType: null, idNumber: '');
    final second = await guests.register(
      desk,
      const GuestForm(
        fullName: 'Tom Achieng',
        phone: '0722418905',
        idType: null,
        idNumber: '',
      ),
    );
    expect([
      for (final g in await guests.withPhone('0722418905')) g.fullName,
    ], unorderedEquals(['Grace Achieng', 'Tom Achieng']));
    expect(
      [
        for (final g in await guests.withPhone(
          '0722418905',
          exceptId: first.id,
        ))
          g.id,
      ],
      [second.id],
    );
  });

  group('guest.update', () {
    test('corrects name, phone and ID; the audit keeps them masked', () async {
      final g = await grace();
      final changed = await guests.update(
        desk,
        g.id,
        const GuestForm(
          fullName: 'Grace Achieng Otieno',
          phone: '0110 234 567',
          idType: IdType.passport,
          idNumber: 'ak1234567',
        ),
      );
      expect(changed, isTrue);
      final now = await guests.guest(g.id);
      expect(
        (now.fullName, now.phone, now.idType, now.idNumber),
        ('Grace Achieng Otieno', '0110234567', IdType.passport, 'AK1234567'),
      );

      final entry = (await env.auditFor('guest.update')).single;
      final before = jsonDecode(entry.beforeJson!) as Map;
      final after = jsonDecode(entry.afterJson) as Map;
      expect(
        (before['full_name'], after['full_name']),
        ('[redacted]', '[redacted]'),
      );
      expect((before['phone'], after['phone']), ('0722•••905', '0110•••567'));
      expect(
        (before['id_number'], after['id_number']),
        ('••••3921', '••••4567'),
      );
    });

    test('nothing changed, nothing written', () async {
      final g = await grace();
      expect(
        await guests.update(
          desk,
          g.id,
          const GuestForm(
            fullName: 'Grace Achieng',
            phone: '0722418905',
            idType: IdType.nationalId,
            idNumber: '12343921',
          ),
        ),
        isFalse,
      );
      expect(await env.auditFor('guest.update'), isEmpty);
    });

    test("can't take another guest's ID, but keeps its own", () async {
      final g = await grace();
      final peter = await guests.register(
        desk,
        const GuestForm(
          fullName: 'Peter Okello',
          phone: '0711000111',
          idType: IdType.nationalId,
          idNumber: '87654321',
        ),
      );
      await expectLater(
        guests.update(
          desk,
          peter.id,
          const GuestForm(
            fullName: 'Peter Okello',
            phone: '0711000111',
            idType: IdType.nationalId,
            idNumber: '12343921',
          ),
        ),
        fieldError(
          GuestField.idNumber,
          'This ID is already registered to another guest.',
        ),
      );
      expect(
        await guests.update(
          desk,
          g.id,
          const GuestForm(
            fullName: 'Grace A.',
            phone: '0722418905',
            idType: IdType.nationalId,
            idNumber: '12343921',
          ),
        ),
        isTrue,
      );
    });

    test('the same rules as registering', () async {
      final g = await grace();
      await expectLater(
        guests.update(
          desk,
          g.id,
          const GuestForm(
            fullName: '',
            phone: '0722418905',
            idType: null,
            idNumber: '',
          ),
        ),
        fieldError(GuestField.fullName, 'Enter the full name.'),
      );
    });
  });
}
