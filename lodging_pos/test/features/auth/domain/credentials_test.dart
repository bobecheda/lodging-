import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/auth/domain/credentials.dart';

void main() {
  group('normalizeUsername', () {
    test('trims and lowercases', () {
      expect(normalizeUsername('  Jane.Doe '), 'jane.doe');
      expect(normalizeUsername('OWNER'), 'owner');
    });
  });

  group('usernameError', () {
    test('accepts 3-32 letters, digits, dot, underscore and dash', () {
      for (final ok in ['abc', 'jane.doe', 'desk_1', 'front-desk', 'a' * 32]) {
        expect(usernameError(ok), isNull, reason: ok);
      }
    });

    test('rejects short, long and other characters', () {
      for (final bad in ['', 'ab', 'a' * 33, 'jane doe', 'jané', 'jane@x']) {
        expect(usernameError(bad), isNotNull, reason: bad);
      }
    });

    test('checks the normalized form', () {
      expect(usernameError('  Jane '), isNull);
    });
  });

  group('passwordError', () {
    test('requires at least 8 characters, no complexity rules', () {
      expect(passwordError('1234567'), isNotNull);
      expect(passwordError('12345678'), isNull);
      expect(passwordError('password'), isNull);
    });
  });

  group('newPasswordErrors', () {
    test('passes a valid matching pair', () {
      expect(newPasswordErrors('longenough', 'longenough'), isEmpty);
    });

    test('reports a short password and a mismatch separately', () {
      expect(newPasswordErrors('short', 'short'), {
        PasswordField.password: passwordError('short'),
      });
      expect(newPasswordErrors('longenough', 'different1'), {
        PasswordField.confirm: 'Passwords do not match',
      });
    });
  });
}
