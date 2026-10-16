import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/auth/domain/idle_lock.dart';

void main() {
  group('idleLockMinutesFrom', () {
    test('reads whole minutes from the setting', () {
      expect(idleLockMinutesFrom('10'), 10);
      expect(idleLockMinutesFrom(' 15 '), 15);
      expect(idleLockMinutesFrom('1'), 1);
      expect(idleLockMinutesFrom('60'), 60);
    });

    test('falls back to the default (10) when missing or invalid', () {
      for (final bad in [null, '', 'ten', '0', '-5', '61', '240', '7.5']) {
        expect(idleLockMinutesFrom(bad), 10, reason: '$bad');
      }
    });
  });

  test('idleLockMinutesError is the one 1–60 validator (AD-3 shares it)', () {
    expect(idleLockMinutesError('1'), isNull);
    expect(idleLockMinutesError(' 60 '), isNull);
    for (final bad in ['0', '61', '', 'x']) {
      expect(
        idleLockMinutesError(bad),
        'Enter whole minutes from 1 to 60.',
        reason: bad,
      );
    }
  });

  group('shouldLock', () {
    final last = DateTime.utc(2026, 10, 14, 19);
    bool lockedAt(Duration idle, {int minutes = 10}) => shouldLock(
      lastActivity: last,
      now: last.add(idle),
      idleMinutes: minutes,
    );

    test('does not lock before the limit', () {
      expect(lockedAt(Duration.zero), isFalse);
      expect(lockedAt(const Duration(minutes: 9, seconds: 59)), isFalse);
    });

    test('locks at and after the limit', () {
      expect(lockedAt(const Duration(minutes: 10)), isTrue);
      expect(lockedAt(const Duration(hours: 3)), isTrue);
    });

    test('uses the configured minutes', () {
      expect(lockedAt(const Duration(minutes: 4), minutes: 5), isFalse);
      expect(lockedAt(const Duration(minutes: 5), minutes: 5), isTrue);
    });

    test('a clock set back never locks early', () {
      expect(lockedAt(const Duration(minutes: -30)), isFalse);
    });
  });
}
