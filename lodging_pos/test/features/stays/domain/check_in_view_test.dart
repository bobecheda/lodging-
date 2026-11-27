import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/stays/domain/check_in.dart';
import 'package:lodging_pos/features/stays/domain/check_in_view.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

BedSummary bed(
  String id, {
  BedLabel label = BedLabel.a,
  String category = 'Comfort',
  int price = 600,
  String colour = 'teal',
  Cleanliness cleanliness = Cleanliness.clean,
  bool isActive = true,
  bool hasActiveStay = false,
}) => BedSummary(
  id: id,
  label: label,
  categoryId: category.toLowerCase(),
  categoryName: category,
  categoryColour: colour,
  pricePerNight: price,
  cleanliness: cleanliness,
  isActive: isActive,
  hasActiveStay: hasActiveStay,
);

RoomSummary room(String number, List<BedSummary> beds) => RoomSummary(
  id: 'room-$number',
  number: number,
  floor: null,
  notes: null,
  isActive: true,
  beds: beds,
);

LetBed let(BedSummary b) => LetBed(
  bedId: b.id,
  categoryId: b.categoryId,
  categoryName: b.categoryName,
  pricePerNight: b.pricePerNight,
);

void main() {
  // Wed 11 Nov 2026, 14:05 Nairobi.
  final now = nairobiInstant(2026, 11, 11, 14, 5);
  const ten = ClockTime(10, 0);

  CheckInQuote quote(List<BedSummary> beds, {int nights = 2}) => quoteCheckIn(
    checkInAt: now,
    nights: nights,
    checkout: ten,
    beds: [for (final b in beds) let(b)],
  );

  group('the bed row', () {
    final a104 = bed('104a');
    final b104 = bed('104b', label: BedLabel.b);

    test('one bed: "104 A", then category and price, and when it was '
        'cleaned', () {
      expect(bedRowTitle('104', [a104]), '104 A');
      expect(bedRowMeta([a104]), 'Comfort · KES 600 a night');
      expect(
        bedRowMeta([a104], cleaned: 'Cleaned 08:15 · Mary'),
        'Comfort · KES 600 a night · cleaned 08:15 · Mary',
      );
    });

    test('the whole room at one price: "each"', () {
      expect(bedRowTitle('107', [a104, b104]), '107 A + 107 B');
      expect(
        bedRowMeta([a104, b104], cleaned: 'Cleaned 08:15 · Mary'),
        'Comfort · KES 600 a night each',
      );
    });

    test('the whole room, two categories at one price', () {
      final deluxe = bed('7b', label: BedLabel.b, category: 'Deluxe');
      expect(
        bedRowMeta([a104, deluxe]),
        'Comfort + Deluxe · KES 600 a night each',
      );
    });

    test('the whole room at two prices', () {
      final deluxe = bed('7a', category: 'Deluxe', price: 700);
      final comfort = bed('7b', label: BedLabel.b);
      expect(bedRowMeta([deluxe, comfort]), 'KES 700 + KES 600 a night');
    });
  });

  group('whole room note', () {
    test('the other bed, named with its room, and why it can’t be let', () {
      final guest = bed('104b', label: BedLabel.b, hasActiveStay: true);
      final dirty = bed(
        '104b',
        label: BedLabel.b,
        cleanliness: Cleanliness.notCleaned,
      );
      final closed = bed('104b', label: BedLabel.b, isActive: false);
      expect(wholeRoomNote('104', guest), '104 B has a guest');
      expect(wholeRoomNote('104', dirty), '104 B needs cleaning first');
      expect(wholeRoomNote('104', closed), '104 B is closed');
      expect(wholeRoomNote('104', bed('104b', label: BedLabel.b)), isNull);
    });

    test('agrees with letBlocker', () {
      final guest = bed('104b', label: BedLabel.b, hasActiveStay: true);
      expect(letBlocker(guest, Occupancy.occupied), 'Bed B has a guest');
    });
  });

  group('the bed chooser', () {
    test('only Ready and clean beds, by category, dearest first, in room '
        'order', () {
      final groups = readyBedGroups([
        room('106', [
          bed('106a', category: 'Normal', price: 500, hasActiveStay: true),
          bed('106b', label: BedLabel.b, category: 'Normal', price: 500),
        ]),
        room('101', [
          bed(
            '101a',
            category: 'Deluxe',
            price: 700,
            cleanliness: Cleanliness.notCleaned,
          ),
          bed('101b', label: BedLabel.b, category: 'Deluxe', price: 700),
        ]),
        room('104', [bed('104a')]),
        room('107', [
          bed('107a', category: 'Normal', price: 500),
          bed('107b', label: BedLabel.b, isActive: false),
        ]),
      ]);
      expect(
        [
          for (final g in groups)
            (
              g.categoryName,
              g.colour,
              g.pricePerNight,
              g.beds.map((b) => b.name).join(', '),
            ),
        ],
        [
          ('Deluxe', 'teal', 700, '101 B'),
          ('Comfort', 'teal', 600, '104 A'),
          ('Normal', 'teal', 500, '106 B, 107 A'),
        ],
      );
      expect(readyBedCount(groups), 4);
    });

    test('no Ready bed: no groups', () {
      expect(
        readyBedGroups([
          room('7', [bed('7a', hasActiveStay: true)]),
        ]),
        isEmpty,
      );
    });
  });

  group('the summary', () {
    test('one bed: nights × price', () {
      expect(checkInPriceLines(nights: 2, beds: [('104 A', 600)]), [
        '2 nights × KES 600',
      ]);
      expect(checkInPriceLines(nights: 1, beds: [('104 A', 600)]), [
        '1 night × KES 600',
      ]);
    });

    test('the whole room at one price: one line, one receipt', () {
      expect(
        checkInPriceLines(nights: 2, beds: [('107 A', 500), ('107 B', 500)]),
        ['2 beds × 2 nights × KES 500 · one receipt'],
      );
    });

    test('the whole room at two prices: a line per bed, then one receipt', () {
      expect(checkInPriceLines(nights: 2, beds: [('7 A', 700), ('7 B', 600)]), [
        '7 A · 2 nights × KES 700',
        '7 B · 2 nights × KES 600 · one receipt',
      ]);
    });
  });

  group('the confirm line', () {
    final a = bed('104a');
    final b = bed('104b', label: BedLabel.b);

    CheckInConfirm confirm({
      CheckInQuote? q,
      bool bedChosen = true,
      String? nightsProblem,
      GuestReadiness guest = GuestReadiness.ready,
      PaymentMethod? method = PaymentMethod.paybill,
    }) => checkInConfirm(
      quote: q,
      bedChosen: bedChosen,
      nightsProblem: nightsProblem,
      guest: guest,
      method: method,
    );

    test('ready: method, total and when they leave', () {
      final line = confirm(q: quote([a]));
      expect(line.ready, isTrue);
      expect(line.text, 'M-Pesa · KES 1,200 · out Fri 10:00');
    });

    test('the whole room says how many beds', () {
      final line = confirm(q: quote([a, b]), method: PaymentMethod.cash);
      expect(line.text, 'Cash · KES 2,400 · 2 beds · out Fri 10:00');
    });

    test('grey until everything is chosen, naming the first thing missing', () {
      expect(
        (confirm(bedChosen: false).ready, confirm(bedChosen: false).text),
        (false, 'Choose a bed'),
      );
      expect(
        confirm(nightsProblem: 'Choose 1 to 30 nights.').text,
        'Choose 1 to 30 nights.',
      );
      // A chosen bed with no quote and no nights problem: the bed can't be
      // let any more.
      expect(confirm().text, 'Choose a bed');
      expect(
        confirm(q: quote([a]), guest: GuestReadiness.none).text,
        'Find or add the guest',
      );
      expect(
        confirm(q: quote([a]), guest: GuestReadiness.incomplete).text,
        'Add the new guest’s name and phone',
      );
      final noMethod = confirm(q: quote([a]), method: null);
      expect((noMethod.ready, noMethod.text), (false, 'Choose Cash or M-Pesa'));
    });
  });

  group('stay count', () {
    test('"3 stays"', () {
      expect(stayCountLabel(0), 'No stays yet');
      expect(stayCountLabel(1), '1 stay');
      expect(stayCountLabel(3), '3 stays');
    });
  });
}
