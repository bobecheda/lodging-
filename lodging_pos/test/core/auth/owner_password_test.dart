import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/auth/owner_password.dart';

void main() {
  final at = nairobiInstant(2026, 10, 25, 9);

  test('the desk’s copy is behind only when the cloud recorded a later '
      'change', () {
    expect(ownerPasswordBehind(cloudAt: null, deskAt: null), isFalse);
    expect(ownerPasswordBehind(cloudAt: null, deskAt: at), isFalse);
    expect(ownerPasswordBehind(cloudAt: at, deskAt: null), isTrue);
    expect(ownerPasswordBehind(cloudAt: at, deskAt: at), isFalse);
    expect(
      ownerPasswordBehind(
        cloudAt: at.add(const Duration(seconds: 1)),
        deskAt: at,
      ),
      isTrue,
    );
    expect(
      ownerPasswordBehind(
        cloudAt: at,
        deskAt: at.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );
  });

  test('the messages', () {
    expect(
      passwordChangedOnPhone,
      'Your password was changed on your phone. Sign in with the new one '
      '(needs internet).',
    );
    expect(
      changingPasswordNeedsInternet,
      'Changing your password needs an internet connection.',
    );
  });
}
