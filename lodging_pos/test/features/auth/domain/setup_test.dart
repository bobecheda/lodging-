import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/auth/domain/setup.dart';

void main() {
  const valid = SetupInput(
    fullName: 'Grace Supervisor',
    username: 'Supervisor',
    password: 'longenough',
    confirmPassword: 'longenough',
    lodgingName: 'Sunrise Lodge',
  );

  test('a complete form has no errors', () {
    expect(validateSetup(valid), isEmpty);
  });

  test('every field is required', () {
    final errors = validateSetup(
      const SetupInput(
        fullName: ' ',
        username: '',
        password: '',
        confirmPassword: '',
        lodgingName: '  ',
      ),
    );
    expect(
      errors.keys,
      containsAll([
        SetupField.fullName,
        SetupField.username,
        SetupField.password,
        SetupField.lodgingName,
      ]),
    );
  });

  test('applies the username and password rules', () {
    final errors = validateSetup(
      valid.copyWith(
        username: 'ab',
        password: 'short',
        confirmPassword: 'short',
      ),
    );
    expect(
      errors.keys,
      containsAll([SetupField.username, SetupField.password]),
    );
  });

  test('password and confirmation must match', () {
    expect(validateSetup(valid.copyWith(confirmPassword: 'longenougH')), {
      SetupField.confirmPassword: 'Passwords do not match',
    });
  });

  test('normalizes what gets saved', () {
    final saved = valid
        .copyWith(
          fullName: '  Grace Supervisor ',
          username: '  Supervisor ',
          lodgingName: ' Sunrise Lodge  ',
        )
        .normalized();
    expect(saved.fullName, 'Grace Supervisor');
    expect(saved.username, 'supervisor');
    expect(saved.lodgingName, 'Sunrise Lodge');
    expect(saved.password, 'longenough');
  });
}
