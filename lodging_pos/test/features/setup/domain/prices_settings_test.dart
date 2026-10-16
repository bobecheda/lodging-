import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/features/setup/domain/bed_category.dart';
import 'package:lodging_pos/features/setup/domain/prices_settings.dart';

BedCategory category(
  String name,
  int price, {
  String? id,
  bool isActive = true,
  int sortOrder = 1,
}) => BedCategory(
  id: id ?? name.toLowerCase(),
  name: name,
  pricePerNight: price,
  sortOrder: sortOrder,
  isActive: isActive,
);

void main() {
  group('priceError (AD-3: whole KES, 1–100,000)', () {
    test('accepts the range', () {
      for (final ok in [1, 500, 100000]) {
        expect(priceError(ok), isNull, reason: '$ok');
      }
    });

    test('refuses missing, zero and too large', () {
      expect(priceError(null), 'Enter a price.');
      expect(priceError(0), 'The price must be at least KES 1.');
      expect(priceError(100001), 'The price can be at most KES 100,000.');
    });
  });

  group('priceChanges', () {
    final categories = [
      category('VIP', 1000),
      category('Deluxe', 700),
      category('Comfort', 600),
    ];

    test('lists only prices that differ, in category order', () {
      final changes = priceChanges(categories, {
        'comfort': 650,
        'vip': 1000, // unchanged
        'deluxe': 750,
      });
      expect(
        [for (final c in changes) c.label],
        ['Deluxe: 700 → 750', 'Comfort: 600 → 650'],
      );
      expect(changes.first.categoryId, 'deluxe');
      expect((changes.first.oldPrice, changes.first.newPrice), (700, 750));
    });

    test('thousands are grouped in the label', () {
      final changes = priceChanges(categories, {'vip': 12500});
      expect(changes.single.label, 'VIP: 1,000 → 12,500');
    });

    test('no edits, no changes', () {
      expect(priceChanges(categories, const {}), isEmpty);
    });
  });

  group('category names (trimmed, 1–30, unique ignoring case)', () {
    final existing = [category('Deluxe', 700), category('VIP', 1000)];

    test('normalizes by trimming', () {
      expect(normalizeCategoryName('  Family room '), 'Family room');
    });

    test('valid new name', () {
      expect(categoryNameError(' Family ', existing: existing), isNull);
    });

    test('empty and too long are refused', () {
      expect(categoryNameError('   ', existing: existing), 'Enter a name.');
      expect(
        categoryNameError('x' * 31, existing: existing),
        'Use at most 30 characters.',
      );
      expect(categoryNameError('x' * 30, existing: existing), isNull);
    });

    test('a name in use, in any case, is refused', () {
      expect(
        categoryNameError(' deluxe ', existing: existing),
        'Deluxe already exists.',
      );
    });
  });

  group('closeCategoryBlocker', () {
    test('a category used by active beds cannot close', () {
      expect(
        closeCategoryBlocker(category('Deluxe', 700), activeBeds: 3),
        '3 beds use Deluxe. Move them to another category first.',
      );
      expect(
        closeCategoryBlocker(category('VIP', 1000), activeBeds: 1),
        '1 bed uses VIP. Move it to another category first.',
      );
    });

    test('an unused category can close; a closed one has nothing to block', () {
      expect(
        closeCategoryBlocker(category('VIP', 1000), activeBeds: 0),
        isNull,
      );
      expect(
        closeCategoryBlocker(
          category('VIP', 1000, isActive: false),
          activeBeds: 0,
        ),
        isNull,
      );
    });
  });

  group('settings', () {
    SettingsInput input({
      String lodgingName = 'Sunrise Lodge',
      ClockTime checkoutTime = const ClockTime(10, 0),
      String graceMinutes = '60',
      String idleLockMinutes = '10',
      String receiptPrefix = 'R',
    }) => SettingsInput(
      lodgingName: lodgingName,
      checkoutTime: checkoutTime,
      graceMinutes: graceMinutes,
      idleLockMinutes: idleLockMinutes,
      receiptPrefix: receiptPrefix,
    );

    test('the defaults are valid', () {
      expect(validateSettings(input()), isEmpty);
    });

    test('lodging name is required, at most 60 characters', () {
      expect(validateSettings(input(lodgingName: '  ')), {
        SettingsField.lodgingName: 'Enter the lodging name.',
      });
      expect(validateSettings(input(lodgingName: 'x' * 61)), {
        SettingsField.lodgingName: 'Use at most 60 characters.',
      });
    });

    test('checkout time is 06:00–14:00 in 30-minute steps', () {
      expect(checkoutTimeOptions.first, const ClockTime(6, 0));
      expect(checkoutTimeOptions.last, const ClockTime(14, 0));
      expect(checkoutTimeOptions, hasLength(17));
      expect(checkoutTimeOptions, contains(const ClockTime(10, 30)));
      for (final bad in [const ClockTime(5, 30), const ClockTime(14, 30)]) {
        expect(validateSettings(input(checkoutTime: bad)), {
          SettingsField.checkoutTime: 'Choose a time from 06:00 to 14:00.',
        });
      }
    });

    test('grace is whole minutes 0–180', () {
      for (final ok in ['0', '60', '180', ' 45 ']) {
        expect(validateSettings(input(graceMinutes: ok)), isEmpty, reason: ok);
      }
      for (final bad in ['', '-1', '181', '7.5', 'ten']) {
        expect(validateSettings(input(graceMinutes: bad)), {
          SettingsField.graceMinutes: 'Enter whole minutes from 0 to 180.',
        }, reason: bad);
      }
    });

    test('lock after is whole minutes 1–60 (the shared validator)', () {
      for (final bad in ['0', '61', '240', '']) {
        expect(validateSettings(input(idleLockMinutes: bad)), {
          SettingsField.idleLockMinutes: 'Enter whole minutes from 1 to 60.',
        }, reason: bad);
      }
      expect(validateSettings(input(idleLockMinutes: '60')), isEmpty);
    });

    test('receipt prefix is 1–4 letters, stored uppercase', () {
      for (final ok in ['R', 'sun', 'ABCD']) {
        expect(validateSettings(input(receiptPrefix: ok)), isEmpty, reason: ok);
      }
      for (final bad in ['', 'ABCDE', 'R1', 'R-']) {
        expect(validateSettings(input(receiptPrefix: bad)), {
          SettingsField.receiptPrefix: 'Use 1 to 4 letters.',
        }, reason: bad);
      }
      expect(input(receiptPrefix: ' sun ').normalized().receiptPrefix, 'SUN');
    });

    test('normalized values are what gets stored', () {
      final stored = input(
        lodgingName: ' Sunrise Lodge ',
        graceMinutes: ' 45 ',
        idleLockMinutes: '15',
        checkoutTime: const ClockTime(9, 30),
      ).normalized().toStored();
      expect(stored, {
        'lodging_name': 'Sunrise Lodge',
        'checkout_time': '09:30',
        'grace_minutes': '45',
        'idle_lock_minutes': '15',
        'receipt_prefix': 'R',
      });
    });

    test('stored values load back, with defaults for anything unusable', () {
      final loaded = SettingsInput.fromStored({
        'lodging_name': 'Sunrise Lodge',
        'checkout_time': 'soon',
        'grace_minutes': '45',
        'idle_lock_minutes': '240',
        'receipt_prefix': 'SUN',
      });
      expect(loaded.lodgingName, 'Sunrise Lodge');
      expect(loaded.checkoutTime, const ClockTime(10, 0));
      expect(loaded.graceMinutes, '45');
      expect(loaded.idleLockMinutes, '10');
      expect(loaded.receiptPrefix, 'SUN');
    });
  });
}
