import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/setup/domain/prices_settings.dart';

PriceChange change(int from, int to) => PriceChange(
  categoryId: 'c-1',
  name: 'Deluxe',
  oldPrice: from,
  newPrice: to,
);

void main() {
  group('a big price change asks first (desk and phone)', () {
    test('more than 50% either way; exactly 50% doesn’t ask', () {
      expect(isBigPriceChange(700, 1050), isFalse); // +50%
      expect(isBigPriceChange(700, 1051), isTrue);
      expect(isBigPriceChange(700, 350), isFalse); // −50%
      expect(isBigPriceChange(700, 349), isTrue);
      expect(isBigPriceChange(700, 750), isFalse);
    });

    test('the question names the change', () {
      expect(
        bigPriceChangeQuestion(change(700, 1200)),
        'Are you sure? Deluxe goes from KES 700 to KES 1,200 a night, 71% '
        'more.',
      );
      expect(
        bigPriceChangeQuestion(change(1000, 300)),
        'Are you sure? Deluxe goes from KES 1,000 to KES 300 a night, 70% '
        'less.',
      );
      expect(change(700, 1200).isBig, isTrue);
      expect(change(700, 750).isBig, isFalse);
    });
  });

  test('losing an edit race says where it was changed first', () {
    expect(
      priceMovedOnMessage(
        'Deluxe',
        currentPrice: 750,
        at: nairobiInstant(2026, 10, 24, 9, 29),
        where: 'on the desk',
      ),
      'Deluxe was changed to KES 750 on the desk · Sat 24 Oct, 09:29. '
      'Check it and save again.',
    );
  });
}
