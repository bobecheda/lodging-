import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/sync/desk_behind.dart';

/// "This desk's data is behind the cloud" (story/desk-db-guards-2): the
/// cloud proves it, or nothing is said. Pure rules.
void main() {
  final found = DateTime.utc(2026, 11, 24, 6, 51);
  final deskLast = DateTime.utc(2026, 11, 11, 8, 3, 57);
  final cloudLast = DateTime.utc(2026, 11, 11, 8, 22, 31);

  DeskHere here({
    int missing = 0,
    int nextReceipt = 51,
    bool openShiftKnown = false,
  }) => DeskHere(
    missingAuditRows: missing,
    lastOwnAuditAt: deskLast,
    nextReceiptNumber: nextReceipt,
    openShiftKnown: openShiftKnown,
  );

  group('deskBehind: at start and before the first push', () {
    test('the 24 Nov case: records this PC lacks, a higher receipt and an '
        'open shift it doesn’t know', () {
      final e = deskBehind(
        here(missing: 21),
        DeskCloudState(
          lastAuditAt: cloudLast,
          topReceipt: 'R-000052',
          openShiftId: '37441d06-272e-4cb3-8455-918760f42006',
        ),
        now: found,
      )!;
      expect(e.reasons, [
        BehindReason.missingRecords,
        BehindReason.higherReceipt,
        BehindReason.unknownOpenShift,
      ]);
      expect(e.foundAt, found);
      expect(e.cloudTopReceipt, 'R-000052');
      expect(e.deskLastReceipt, 'R-000050');
      expect(e.missingAuditRows, 21);
    });

    test('by ids, not times: a restored desk that has done newer work '
        'offline since is still caught', () {
      expect(
        deskBehind(
          here(missing: 3, nextReceipt: 60),
          const DeskCloudState(topReceipt: 'R-000052'),
          now: found,
        )!.reasons,
        [BehindReason.missingRecords],
      );
    });

    test('each proof alone is enough', () {
      expect(
        deskBehind(
          here(missing: 1),
          DeskCloudState(lastAuditAt: cloudLast),
          now: found,
        )!.reasons,
        [BehindReason.missingRecords],
      );
      expect(
        deskBehind(
          here(),
          const DeskCloudState(topReceipt: 'R-000051'),
          now: found,
        )!.reasons,
        [BehindReason.higherReceipt],
      );
      expect(
        deskBehind(
          here(),
          const DeskCloudState(openShiftId: 'shift-x'),
          now: found,
        )!.reasons,
        [BehindReason.unknownOpenShift],
      );
    });

    test('a desk ahead of the cloud (rows not sent yet) is not behind', () {
      expect(
        deskBehind(
          here(nextReceipt: 60, openShiftKnown: true),
          const DeskCloudState(
            topReceipt: 'R-000052',
            openShiftId: 'closed-here-close-not-sent',
          ),
          now: found,
        ),
        isNull,
      );
      expect(deskBehind(here(), const DeskCloudState(), now: found), isNull);
      expect(
        deskBehind(
          here(),
          const DeskCloudState(topReceipt: 'R-000050'),
          now: found,
        ),
        isNull,
        reason: 'the last receipt this PC issued is R-000050',
      );
    });

    test('receipt numbers compare by their serial, whatever the prefix', () {
      expect(
        deskBehind(
          here(nextReceipt: 100),
          const DeskCloudState(topReceipt: 'UB-000099'),
          now: found,
        ),
        isNull,
      );
    });
  });

  group('refusals and pulled rows that prove it', () {
    test('the cloud refusing a receipt number or a second open shift', () {
      expect(
        behindFromRefusal(
          'payments 4dbd49f2: duplicate key value violates unique '
          'constraint "payments_receipt_number_key"',
          detail: 'R-000051',
          now: found,
        )!.reasons,
        [BehindReason.receiptTaken],
      );
      expect(
        behindFromRefusal(
          'refunds r1: duplicate key value violates unique constraint '
          '"refunds_receipt_number_key"',
          now: found,
        )!.reasons,
        [BehindReason.receiptTaken],
      );
      expect(
        behindFromRefusal(
          'shifts 6b3d50cf: duplicate key value violates unique constraint '
          '"shifts_one_open_per_device"',
          now: found,
        )!.reasons,
        [BehindReason.openShiftTaken],
      );
    });

    test('any other refusal is an ordinary sync problem', () {
      expect(
        behindFromRefusal(
          'payments p1: duplicate key value violates unique constraint '
          '"payments_mpesa_code_nocase"',
          now: found,
        ),
        isNull,
      );
      expect(behindFromRefusal('the cloud is busy', now: found), isNull);
    });

    test('the constraints named here are the cloud’s', () {
      expect(behindConstraints, {
        'payments_receipt_number_key': BehindReason.receiptTaken,
        'refunds_receipt_number_key': BehindReason.receiptTaken,
        'shifts_one_open_per_device': BehindReason.openShiftTaken,
      });
      expect(recentAuditLimit, 50, reason: 'desk_cloud_state returns as many');
    });

    test('a pulled decision about something this PC doesn’t have', () {
      final e = behindFromMissing('a review of shift 37441d06', now: found);
      expect(e.reasons, [BehindReason.missingSubject]);
      expect(e.detail, 'a review of shift 37441d06');
    });
  });

  group('the evidence', () {
    final cloud = DeskCloudState(
      lastAuditAt: cloudLast,
      topReceipt: 'R-000052',
      openShiftId: '37441d06-272e-4cb3-8455-918760f42006',
    );

    test(
      'survives JSON (it is kept on the desk until the technician sorts it)',
      () {
        final e = deskBehind(here(missing: 21), cloud, now: found)!;
        final back = BehindEvidence.fromJson(e.toJson());
        expect(back.reasons, e.reasons);
        expect(back.foundAt, found);
        expect(back.cloudLastAuditAt, cloudLast);
        expect(back.deskLastAuditAt, deskLast);
        expect(back.cloudOpenShiftId, cloud.openShiftId);
        expect(back.missingAuditRows, 21);
      },
    );

    test('the owner’s details are plain lines, with both sides', () {
      expect(deskBehind(here(missing: 21), cloud, now: found)!.lines(), [
        'The cloud has 21 records from this desk that this PC doesn’t have '
            '(the cloud’s newest: Wed 11 Nov · 11:22; this PC’s newest: '
            'Wed 11 Nov · 11:03).',
        'The cloud has receipt R-000052 from this desk; this PC’s last is '
            'R-000050.',
        'The cloud has an open shift from this desk (37441d06) that this '
            'PC doesn’t have.',
      ]);
      expect(
        deskBehind(
          here(missing: recentAuditLimit),
          const DeskCloudState(),
          now: found,
        )!.lines().single,
        startsWith('The cloud has $recentAuditLimit or more records'),
      );
      expect(
        behindFromRefusal(
          'payments p: duplicate key value violates unique constraint '
          '"payments_receipt_number_key"',
          detail: 'R-000051',
          now: found,
        )!.lines(),
        ['The cloud already has receipt R-000051 from this desk.'],
      );
      expect(
        behindFromRefusal(
          'shifts s: duplicate key value violates unique constraint '
          '"shifts_one_open_per_device"',
          now: found,
        )!.lines(),
        ['The cloud already has an open shift from this desk.'],
      );
      expect(
        behindFromMissing('a review of shift 37441d06', now: found).lines(),
        [
          'The cloud has a review of shift 37441d06, which this PC doesn’t '
              'have.',
        ],
      );
    });
  });
}
