import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/owner_app/domain/owner_today.dart';

void main() {
  final now = nairobiInstant(2026, 10, 24, 9, 30);

  DeskStatus desk({
    required Duration ago,
    int pending = 0,
    String? problem,
    String id = 'dev-1',
  }) => DeskStatus(
    deviceId: id,
    reportedAt: now.subtract(ago),
    pending: pending,
    problem: problem,
  );

  group('the desk line', () {
    test('no desk yet', () {
      final line = deskLine(const [], now);
      expect(line.text, 'The desk isn’t connected to the cloud yet.');
      expect(line.online, isFalse);
    });

    test('heard from in the last 11 minutes: online, with what waits', () {
      expect(
        deskLine([desk(ago: const Duration(minutes: 4))], now).text,
        'Desk online · up to date',
      );
      expect(
        deskLine([desk(ago: const Duration(minutes: 11), pending: 1)], now),
        isA<DeskLine>()
            .having((l) => l.text, 'text', 'Desk online · 1 change waiting')
            .having((l) => l.online, 'online', isTrue),
      );
      expect(
        deskLine([desk(ago: Duration.zero, pending: 12)], now).text,
        'Desk online · 12 changes waiting',
      );
      expect(
        deskLine([desk(ago: Duration.zero, problem: 'refused')], now).text,
        'Desk online · sync problem',
      );
    });

    test('silent for longer: offline since it was last heard from', () {
      final line = deskLine([desk(ago: const Duration(minutes: 12))], now);
      expect(line.text, 'Desk offline · last seen today 09:18');
      expect(line.online, isFalse);
      expect(
        deskLine([desk(ago: const Duration(hours: 14))], now).text,
        'Desk offline · last seen yesterday 19:30',
      );
    });

    test('two desks: the latest one heard from', () {
      expect(
        deskLine([
          desk(ago: const Duration(hours: 3), id: 'old'),
          desk(ago: const Duration(minutes: 2), pending: 3),
        ], now).text,
        'Desk online · 3 changes waiting',
      );
    });
  });

  group('the updated line', () {
    final at = nairobiInstant(2026, 10, 24, 9, 15);
    test('online: how long ago', () {
      expect(updatedLine(at, at, offline: false), 'Updated just now');
      expect(
        updatedLine(at, at.add(const Duration(seconds: 59)), offline: false),
        'Updated just now',
      );
      expect(
        updatedLine(at, at.add(const Duration(minutes: 1)), offline: false),
        'Updated 1 min ago',
      );
      expect(
        updatedLine(at, at.add(const Duration(minutes: 59)), offline: false),
        'Updated 59 min ago',
      );
      expect(
        updatedLine(at, at.add(const Duration(hours: 2)), offline: false),
        'Updated today 09:15',
      );
    });

    test('offline: when the shown figures are from', () {
      expect(
        updatedLine(at, at.add(const Duration(minutes: 3)), offline: true),
        'Offline · showing today 09:15',
      );
    });
  });

  group('needs your attention, besides refunds and prices', () {
    test('cash short at a shift close in the last 7 days, oldest first', () {
      final shifts = [
        ClosedShift(
          shiftId: 's-ok',
          userName: 'Mary Wanjiku',
          closedAt: now.subtract(const Duration(hours: 2)),
          variance: 0,
        ),
        ClosedShift(
          shiftId: 's-over',
          userName: 'Mary Wanjiku',
          closedAt: now.subtract(const Duration(hours: 3)),
          variance: 200,
        ),
        ClosedShift(
          shiftId: 's-late',
          userName: 'John Otieno',
          closedAt: now.subtract(const Duration(hours: 1)),
          variance: -300,
        ),
        ClosedShift(
          shiftId: 's-early',
          userName: 'Mary Wanjiku',
          closedAt: now.subtract(const Duration(days: 2)),
          variance: -50,
        ),
        ClosedShift(
          shiftId: 's-old',
          userName: 'Mary Wanjiku',
          closedAt: now.subtract(const Duration(days: 7, minutes: 1)),
          variance: -900,
        ),
      ];
      final short = shortages(shifts, now);
      expect([for (final s in short) s.shiftId], ['s-early', 's-late']);
      expect(short.last.title, 'Cash short at shift close');
      expect(short.last.subtitle(now), 'John · today 08:30');
      expect(short.last.figure, 'KES 300');
    });

    test('a voided payment', () {
      final v = PaymentVoided(
        voidId: 'v-1',
        receiptNumber: 'R-000041',
        amount: 1400,
        reason: 'Wrong bed',
        voidedBy: 'Grace Akinyi',
        voidedAt: nairobiInstant(2026, 10, 23, 18, 40),
      );
      expect(v.title, 'Payment voided · R-000041');
      expect(v.subtitle(now), 'Wrong bed · by Grace · yesterday 18:40');
      expect(v.figure, 'KES 1,400');
    });

    test('attention looks back 7 days', () {
      expect(attentionSince(now), now.subtract(const Duration(days: 7)));
    });
  });
}
