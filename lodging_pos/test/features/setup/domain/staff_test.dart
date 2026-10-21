import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/setup/domain/staff.dart';

UserAccount account(
  String id,
  String fullName, {
  Role role = Role.receptionist,
  bool isActive = true,
  bool mustChangePassword = false,
}) => UserAccount(
  id: id,
  fullName: fullName,
  username: id,
  role: role,
  isActive: isActive,
  mustChangePassword: mustChangePassword,
);

void main() {
  final supervisor = account(
    'supervisor',
    'Grace Supervisor',
    role: Role.supervisor,
  );
  final mary = account('mary', 'Mary Wanjiku');

  group('validateNewReceptionist', () {
    NewReceptionist input({
      String fullName = 'Mary Wanjiku',
      String username = 'Mary',
      String password = 'temp-pass-1',
    }) => NewReceptionist(
      fullName: fullName,
      username: username,
      temporaryPassword: password,
    );

    test('a valid form has no errors and normalizes', () {
      expect(validateNewReceptionist(input()), isEmpty);
      final n = input(
        fullName: ' Mary Wanjiku ',
        username: ' Mary ',
      ).normalized();
      expect((n.fullName, n.username), ('Mary Wanjiku', 'mary'));
    });

    test('each field says what is wrong', () {
      expect(
        validateNewReceptionist(
          input(fullName: ' ', username: 'x', password: 'short'),
        ),
        {
          ReceptionistField.fullName: 'Enter the full name.',
          ReceptionistField.username:
              '3–32 characters: letters, digits, dot, underscore or dash',
          ReceptionistField.temporaryPassword: 'At least 8 characters',
        },
      );
      expect(validateNewReceptionist(input(fullName: 'x' * 61)), {
        ReceptionistField.fullName: 'Use at most 60 characters.',
      });
    });
  });

  group('userStatus', () {
    test('disabled wins, then must set password, else active', () {
      expect(userStatus(mary), UserStatus.active);
      expect(
        userStatus(mary.copyWith(mustChangePassword: true)),
        UserStatus.mustSetPassword,
      );
      expect(
        userStatus(mary.copyWith(isActive: false, mustChangePassword: true)),
        UserStatus.disabled,
      );
    });
  });

  group('account actions', () {
    test('nobody disables or resets their own account here', () {
      expect(
        accountActionBlocker(actor: supervisor, target: supervisor),
        "You can't change your own account here.",
      );
      expect(accountActionBlocker(actor: supervisor, target: mary), isNull);
    });

    test('a supervisor or the owner is not managed from this list', () {
      final other = account('s2', 'Other Supervisor', role: Role.supervisor);
      expect(
        accountActionBlocker(actor: supervisor, target: other),
        "A supervisor's account can't be changed here.",
      );
      final owner = account('o1', 'Amina Owner', role: Role.owner);
      expect(
        accountActionBlocker(actor: supervisor, target: owner),
        "The owner's account can't be changed here.",
      );
    });
  });

  group('disableWarning', () {
    test("warns when the user's shift is still open", () {
      expect(
        disableWarning(
          mary,
          shiftOpenSince: nairobiInstant(2026, 10, 16, 7, 2),
        ),
        "Mary's shift is still open (since 07:02). Until shift close exists, "
        'no other receptionist can open a shift on this desk.',
      );
    });

    test('no open shift, no warning', () {
      expect(disableWarning(mary, shiftOpenSince: null), isNull);
    });
  });

  group('housekeepers', () {
    test('name is required, at most 60; the phone is optional', () {
      expect(housekeeperErrors(name: 'Rose Akinyi', phone: ''), isEmpty);
      expect(housekeeperErrors(name: ' ', phone: ''), {
        HousekeeperField.name: 'Enter the name.',
      });
      expect(housekeeperErrors(name: 'x' * 61, phone: ''), {
        HousekeeperField.name: 'Use at most 60 characters.',
      });
    });

    test('a phone, if given, must be a Kenyan 07/01 number', () {
      expect(
        housekeeperErrors(name: 'Rose', phone: '+254 722 123 310'),
        isEmpty,
      );
      expect(housekeeperErrors(name: 'Rose', phone: '0822123310'), {
        HousekeeperField.phone:
            'Enter a Kenyan number starting 07 or 01, e.g. 0722 123 310.',
      });
    });

    test('what gets stored: trimmed name, 10-digit phone or null', () {
      expect(
        NewHousekeeper.fromForm(name: ' Rose Akinyi ', phone: '0722-123-310'),
        isA<NewHousekeeper>()
            .having((h) => h.fullName, 'name', 'Rose Akinyi')
            .having((h) => h.phone, 'phone', '0722123310'),
      );
      expect(NewHousekeeper.fromForm(name: 'John', phone: '  ').phone, isNull);
    });
  });
}
